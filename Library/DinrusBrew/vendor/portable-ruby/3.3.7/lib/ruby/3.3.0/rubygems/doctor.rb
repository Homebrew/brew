# frozen_string_literal: true

require_relative "../rubygems"
require_relative "user_interaction"

##
# Cleans up after a partially-failed uninstall or for an invalid
# Gem::Specification.
#
# If a specification was removed by hand this will remove any remaining files.
#
# If a corrupt specification was installed this will clean up warnings by
# removing the bogus specification.

class Gem::Doctor
  include Gem::UserInteraction

  ##
  # Maps a gem subdirectory to the files that are expected to exist in the
  # subdirectory.

  REPOSITORY_EXTENSION_MAP = [ # :nodoc:
    ["specifications", ".gemspec"],
    ["build_info",     ".info"],
    ["cache",          ".gem"],
    ["doc",            ""],
    ["extensions",     ""],
    ["gems",           ""],
    ["plugins",        ""],
  ].freeze

  missing =
    Gem::REPOSITORY_SUBDIRECTORIES.sort -
    REPOSITORY_EXTENSION_MAP.map {|(k,_)| k }.sort

  raise "Update REPOSITORY_EXTENSION_MAP, missing: #{missing.join ", "}" unless
    missing.empty?

  ##
  # Creates a new Gem::Doctor that will clean up +gem_repository+.  Only one
  # gem repository may be cleaned at a time.
  #
  # If +dry_run+ is true no files or directories will be removed.

  def initialize(gem_repository, dry_run = false)
    @gem_repository = gem_repository
    @dry_run        = dry_run

    @installed_specs = nil
  end

  ##
  # Specs installed in this gem repository

  def installed_specs # :nodoc:
    @installed_specs ||= Gem::Specification.map(&:full_name)
  end

  ##
  # Are we doctoring a gem repository?

  def gem_repository?
    !installed_specs.empty?
  end

  ##
  # Cleans up uninstalled files and invalid gem specifications

  def doctor
    @orig_home = Gem.dir
    @orig_path = Gem.path

    say "Checking #{@gem_repository}"

    Gem.use_paths @gem_repository.to_s

    unless gem_repository?
      say "This directory does not appear to be a RubyGems repository, " \
          "skipping"
      say
      return
    end

    doctor_children

    say
  ensure
    Gem.use_paths @orig_home, *@orig_path
  end

  ##
  # Cleans up children of this gem repository

  def doctor_children # :nodoc:
    REPOSITORY_EXTENSION_MAP.each do |sub_directory, extension|
      doctor_child sub_directory, extension
    end
  end

  ##
  # Removes files in +sub_directory+ with +extension+

  def doctor_child(sub_directory, extension) # :nodoc:
    directory = File.join(@gem_repository, sub_directory)

    Dir.entries(directory).sort.each do |ent|
      next if [".", ".."].include?(ent)

      child = File.join(directory, ent)
      next unless File.exist?(child)

      basename = File.basename(child, extension)
      next if installed_specs.include? basename
      next if /^rubygems-\d/.match?(basename)
      next if sub_directory == "specifications" && basename == "default"
      next if sub_directory == "plugins" && Gem.plugin_suffix_regexp =~ (basename)

      type = File.directory?(child) ? "directory" : "file"

      action = if @dry_run
        "Extra"
      else
        FileUtils.rm_r(child)
        "Removed"
      end

      say "#{action} #{type} #{sub_directory}/#{File.basename(child)}"
    end
  rescue Errno::ENOENT
    # ignore
  end
end
