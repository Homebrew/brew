# frozen_string_literal: true

require_relative "../command"
require_relative "../version_option"
require_relative "../security_option"
require_relative "../remote_fetcher"
require_relative "../package"

# forward-declare

module Gem::Security # :nodoc:
  class Policy # :nodoc:
  end
end

class Gem::Commands::UnpackCommand < Gem::Command
  include Gem::VersionOption
  include Gem::SecurityOption

  def initialize
    require "fileutils"

    super "unpack", "Unpack an installed gem to the current directory",
          version: Gem::Requirement.default,
          target: Dir.pwd

    add_option("--target=DIR",
               "target directory for unpacking") do |value, options|
      options[:target] = value
    end

    add_option("--spec", "unpack the gem specification") do |_value, options|
      options[:spec] = true
    end

    add_security_option
    add_version_option
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to unpack"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def description
    <<-EOF
The unpack command allows you to examine the contents of a gem or modify
them to help diagnose a bug.

You can add the contents of the unpacked gem to the load path using the
RUBYLIB environment variable or -I:

  $ gem unpack my_gem
  Unpacked gem: '.../my_gem-1.0'
  [edit my_gem-1.0/lib/my_gem.rb]
  $ ruby -Imy_gem-1.0/lib -S other_program

You can repackage an unpacked gem using the build command.  See the build
command help for an example.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  #--
  # TODO: allow, e.g., 'gem unpack rake-0.3.1'.  Find a general solution for
  # this, so that it works for uninstall as well.  (And check other commands
  # at the same time.)

  def execute
    security_policy = options[:security_policy]

    get_all_gem_names.each do |name|
      dependency = Gem::Dependency.new name, options[:version]
      path = get_path dependency

      unless path
        alert_error "Gem '#{name}' not installed nor fetchable."
        next
      end

      if @options[:spec]
        spec, metadata = Gem::Package.raw_spec(path, security_policy)

        if metadata.nil?
          alert_error "--spec is unsupported on '#{name}' (old format gem)"
          next
        end

        spec_file = File.basename spec.spec_file

        FileUtils.mkdir_p @options[:target] if @options[:target]

        destination = if @options[:target]
          File.join @options[:target], spec_file
        else
          spec_file
        end

        File.open destination, "w" do |io|
          io.write metadata
        end
      else
        basename = File.basename path, ".gem"
        target_dir = File.expand_path basename, options[:target]

        package = Gem::Package.new path, security_policy
        package.extract_files target_dir

        say "Unpacked gem: '#{target_dir}'"
      end
    end
  end

  ##
  #
  # Find cached filename in Gem.path. Returns nil if the file cannot be found.
  #
  #--
  # TODO: see comments in get_path() about general service.

  def find_in_cache(filename)
    Gem.path.each do |path|
      this_path = File.join(path, "cache", filename)
      return this_path if File.exist? this_path
    end

    nil
  end

  ##
  # Return the full path to the cached gem file matching the given
  # name and version requirement.  Returns 'nil' if no match.
  #
  # Example:
  #
  #   get_path 'rake', '> 0.4' # "/usr/lib/ruby/gems/1.8/cache/rake-0.4.2.gem"
  #   get_path 'rake', '< 0.1' # nil
  #   get_path 'rak'           # nil (exact name required)
  #--
  # TODO: This should be refactored so that it's a general service. I don't
  # think any of our existing classes are the right place though.  Just maybe
  # 'Cache'?
  #
  # TODO: It just uses Gem.dir for now.  What's an easy way to get the list of
  # source directories?

  def get_path(dependency)
    return dependency.name if /\.gem$/i.match?(dependency.name)

    specs = dependency.matching_specs

    selected = specs.max_by(&:version)

    return Gem::RemoteFetcher.fetcher.download_to_cache(dependency) unless
      selected

    return unless /^#{selected.name}$/i.match?(dependency.name)

    # We expect to find (basename).gem in the 'cache' directory.  Furthermore,
    # the name match must be exact (ignoring case).

    path = find_in_cache File.basename selected.cache_file

    return Gem::RemoteFetcher.fetcher.download_to_cache(dependency) unless path

    path
  end
end
