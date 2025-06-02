# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require "fileutils"
require_relative "../rubygems"
require_relative "installer_uninstaller_utils"
require_relative "dependency_list"
require_relative "rdoc"
require_relative "user_interaction"

##
# An Uninstaller.
#
# The uninstaller fires pre and post uninstall hooks.  Hooks can be added
# either through a rubygems_plugin.rb file in an installed gem or via a
# rubygems/defaults/#{RUBY_ENGINE}.rb or rubygems/defaults/operating_system.rb
# file.  See Gem.pre_uninstall and Gem.post_uninstall for details.

class Gem::Uninstaller
  include Gem::UserInteraction

  include Gem::InstallerUninstallerUtils

  ##
  # The directory a gem's executables will be installed into

  attr_reader :bin_dir

  ##
  # The gem repository the gem will be uninstalled from

  attr_reader :gem_home

  ##
  # The Gem::Specification for the gem being uninstalled, only set during
  # #uninstall_gem

  attr_reader :spec

  ##
  # Constructs an uninstaller that will uninstall +gem+

  def initialize(gem, options = {})
    # TODO: document the valid options
    @gem                = gem
    @version            = options[:version] || Gem::Requirement.default
    @install_dir        = options[:install_dir]
    @gem_home           = File.realpath(@install_dir || Gem.dir)
    @user_dir           = File.exist?(Gem.user_dir) ? File.realpath(Gem.user_dir) : Gem.user_dir
    @force_executables  = options[:executables]
    @force_all          = options[:all]
    @force_ignore       = options[:ignore]
    @bin_dir            = options[:bin_dir]
    @format_executable  = options[:format_executable]
    @abort_on_dependent = options[:abort_on_dependent]

    # Indicate if development dependencies should be checked when
    # uninstalling. (default: false)
    #
    @check_dev = options[:check_dev]

    if options[:force]
      @force_all = true
      @force_ignore = true
    end

    # only add user directory if install_dir is not set
    @user_install = false
    @user_install = options[:user_install] unless @install_dir

    # Optimization: populated during #uninstall
    @default_specs_matching_uninstall_params = []
  end

  ##
  # Performs the uninstall of the gem.  This removes the spec, the Gem
  # directory, and the cached .gem file.

  def uninstall
    dependency = Gem::Dependency.new @gem, @version

    list = []

    specification_record.stubs.each do |spec|
      next unless dependency.matches_spec? spec

      list << spec
    end

    if list.empty?
      raise Gem::InstallError, "gem #{@gem.inspect} is not installed"
    end

    default_specs, list = list.partition(&:default_gem?)
    warn_cannot_uninstall_default_gems(default_specs - list)
    @default_specs_matching_uninstall_params = default_specs.map(&:to_spec)

    list, other_repo_specs = list.partition do |spec|
      @gem_home == spec.base_dir ||
        (@user_install && spec.base_dir == @user_dir)
    end

    list.sort!

    if list.empty?
      return unless other_repo_specs.any?

      other_repos = other_repo_specs.map(&:base_dir).uniq

      message = ["#{@gem} is not installed in GEM_HOME, try:"]
      message.concat other_repos.map {|repo|
        "\tgem uninstall -i #{repo} #{@gem}"
      }

      raise Gem::InstallError, message.join("\n")
    elsif @force_all
      remove_all list

    elsif list.size > 1
      gem_names = list.map(&:full_name_with_location)
      gem_names << "All versions"

      say
      _, index = choose_from_list "Select gem to uninstall:", gem_names

      if index == list.size
        remove_all list
      elsif index && index >= 0 && index < list.size
        uninstall_gem list[index]
      else
        say "Error: must enter a number [1-#{list.size + 1}]"
      end
    else
      uninstall_gem list.first
    end
  end

  ##
  # Uninstalls gem +spec+

  def uninstall_gem(stub)
    spec = stub.to_spec

    @spec = spec

    unless dependencies_ok? spec
      if abort_on_dependent? || !ask_if_ok(spec)
        raise Gem::DependencyRemovalException,
          "Uninstallation aborted due to dependent gem(s)"
      end
    end

    Gem.pre_uninstall_hooks.each do |hook|
      hook.call self
    end

    remove_executables @spec
    remove_plugins @spec
    remove @spec

    specification_record.remove_spec(stub)

    regenerate_plugins

    Gem.post_uninstall_hooks.each do |hook|
      hook.call self
    end

    @spec = nil
  end

  ##
  # Removes installed executables and batch files (windows only) for +spec+.

  def remove_executables(spec)
    return if spec.executables.empty? || default_spec_matches?(spec)

    executables = spec.executables.clone

    # Leave any executables created by other installed versions
    # of this gem installed.

    list = Gem::Specification.find_all do |s|
      s.name == spec.name && s.version != spec.version
    end

    list.each do |s|
      s.executables.each do |exe_name|
        executables.delete exe_name
      end
    end

    return if executables.empty?

    executables = executables.map {|exec| formatted_program_filename exec }

    remove = if @force_executables.nil?
      ask_yes_no("Remove executables:\n" \
                 "\t#{executables.join ", "}\n\n" \
                 "in addition to the gem?",
                 true)
    else
      @force_executables
    end

    if remove
      bin_dir = @bin_dir || Gem.bindir(spec.base_dir)

      raise Gem::FilePermissionError, bin_dir unless File.writable? bin_dir

      executables.each do |exe_name|
        say "Removing #{exe_name}"

        exe_file = File.join bin_dir, exe_name

        safe_delete { FileUtils.rm exe_file }
        safe_delete { FileUtils.rm "#{exe_file}.bat" }
      end
    else
      say "Executables and scripts will remain installed."
    end
  end

  ##
  # Removes all gems in +list+.
  #
  # NOTE: removes uninstalled gems from +list+.

  def remove_all(list)
    list.each {|spec| uninstall_gem spec }
  end

  ##
  # spec:: the spec of the gem to be uninstalled

  def remove(spec)
    unless path_ok?(@gem_home, spec) ||
           (@user_install && path_ok?(@user_dir, spec))
      e = Gem::GemNotInHomeException.new \
        "Gem '#{spec.full_name}' is not installed in directory #{@gem_home}"
      e.spec = spec

      raise e
    end

    raise Gem::FilePermissionError, spec.base_dir unless
      File.writable?(spec.base_dir)

    full_gem_path = spec.full_gem_path
    exclusions = []

    if default_spec_matches?(spec) && spec.executables.any?
      exclusions = spec.executables.map {|exe| File.join(spec.bin_dir, exe) }
      exclusions << File.dirname(exclusions.last) until exclusions.last == full_gem_path
    end

    safe_delete { rm_r full_gem_path, exclusions: exclusions }
    safe_delete { FileUtils.rm_r spec.extension_dir }

    old_platform_name = spec.original_name

    gem = spec.cache_file
    gem = File.join(spec.cache_dir, "#{old_platform_name}.gem") unless
      File.exist? gem

    safe_delete { FileUtils.rm_r gem }

    begin
      Gem::RDoc.new(spec).remove
    rescue NameError
    end

    gemspec = spec.spec_file

    unless File.exist? gemspec
      gemspec = File.join(File.dirname(gemspec), "#{old_platform_name}.gemspec")
    end

    safe_delete { FileUtils.rm_r gemspec }
    announce_deletion_of(spec)
  end

  ##
  # Remove any plugin wrappers for +spec+.

  def remove_plugins(spec) # :nodoc:
    return if spec.plugins.empty?

    remove_plugins_for(spec, plugin_dir_for(spec))
  end

  ##
  # Regenerates plugin wrappers after removal.

  def regenerate_plugins
    latest = specification_record.latest_spec_for(@spec.name)
    return if latest.nil?

    regenerate_plugins_for(latest, plugin_dir_for(@spec))
  end

  ##
  # Is +spec+ in +gem_dir+?

  def path_ok?(gem_dir, spec)
    full_path     = File.join gem_dir, "gems", spec.full_name
    original_path = File.join gem_dir, "gems", spec.original_name

    full_path == spec.full_gem_path || original_path == spec.full_gem_path
  end

  ##
  # Returns true if it is OK to remove +spec+ or this is a forced
  # uninstallation.

  def dependencies_ok?(spec) # :nodoc:
    return true if @force_ignore

    deplist = Gem::DependencyList.from_specs
    deplist.ok_to_remove?(spec.full_name, @check_dev)
  end

  ##
  # Should the uninstallation abort if a dependency will go unsatisfied?
  #
  # See ::new.

  def abort_on_dependent? # :nodoc:
    @abort_on_dependent
  end

  ##
  # Asks if it is OK to remove +spec+.  Returns true if it is OK.

  def ask_if_ok(spec) # :nodoc:
    msg = [""]
    msg << "You have requested to uninstall the gem:"
    msg << "\t#{spec.full_name}"
    msg << ""

    siblings = Gem::Specification.select do |s|
      s.name == spec.name && s.full_name != spec.full_name
    end

    spec.dependent_gems(@check_dev).each do |dep_spec, dep, _satlist|
      unless siblings.any? {|s| s.satisfies_requirement? dep }
        msg << "#{dep_spec.name}-#{dep_spec.version} depends on #{dep}"
      end
    end

    msg << "If you remove this gem, these dependencies will not be met."
    msg << "Continue with Uninstall?"
    ask_yes_no(msg.join("\n"), false)
  end

  ##
  # Returns the formatted version of the executable +filename+

  def formatted_program_filename(filename) # :nodoc:
    # TODO perhaps the installer should leave a small manifest
    # of what it did for us to find rather than trying to recreate
    # it again.
    if @format_executable
      require_relative "installer"
      Gem::Installer.exec_format % File.basename(filename)
    else
      filename
    end
  end

  def safe_delete(&block)
    block.call
  rescue Errno::ENOENT
    nil
  rescue Errno::EPERM
    e = Gem::UninstallError.new
    e.spec = @spec

    raise e
  end

  private

  def rm_r(path, exclusions:)
    FileUtils::Entry_.new(path).postorder_traverse do |ent|
      ent.remove unless exclusions.include?(ent.path)
    end
  end

  def specification_record
    @specification_record ||= @install_dir ? Gem::SpecificationRecord.from_path(@install_dir) : Gem::Specification.specification_record
  end

  def announce_deletion_of(spec)
    name = spec.full_name
    say "Successfully uninstalled #{name}"
    if default_spec_matches?(spec)
      say(
        "There was both a regular copy and a default copy of #{name}. The " \
          "regular copy was successfully uninstalled, but the default copy " \
          "was left around because default gems can't be removed."
      )
    end
  end

  # @return true if the specs of any default gems are `==` to the given `spec`.
  def default_spec_matches?(spec)
    !default_specs_that_match(spec).empty?
  end

  # @return [Array] specs of default gems that are `==` to the given `spec`.
  def default_specs_that_match(spec)
    @default_specs_matching_uninstall_params.select {|default_spec| spec == default_spec }
  end

  def warn_cannot_uninstall_default_gems(specs)
    specs.each do |spec|
      say "Gem #{spec.full_name} cannot be uninstalled because it is a default gem"
    end
  end

  def plugin_dir_for(spec)
    Gem.plugindir(spec.base_dir)
  end
end
