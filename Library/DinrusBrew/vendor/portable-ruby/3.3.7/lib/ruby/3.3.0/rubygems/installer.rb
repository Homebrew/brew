# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "installer_uninstaller_utils"
require_relative "exceptions"
require_relative "deprecate"
require_relative "package"
require_relative "ext"
require_relative "user_interaction"

##
# The installer installs the files contained in the .gem into the Gem.home.
#
# Gem::Installer does the work of putting files in all the right places on the
# filesystem including unpacking the gem into its gem dir, installing the
# gemspec in the specifications dir, storing the cached gem in the cache dir,
# and installing either wrappers or symlinks for executables.
#
# The installer invokes pre and post install hooks.  Hooks can be added either
# through a rubygems_plugin.rb file in an installed gem or via a
# rubygems/defaults/#{RUBY_ENGINE}.rb or rubygems/defaults/operating_system.rb
# file.  See Gem.pre_install and Gem.post_install for details.

class Gem::Installer
  extend Gem::Deprecate

  ##
  # Paths where env(1) might live.  Some systems are broken and have it in
  # /bin

  ENV_PATHS = %w[/usr/bin/env /bin/env].freeze

  ##
  # Deprecated in favor of Gem::Ext::BuildError

  ExtensionBuildError = Gem::Ext::BuildError # :nodoc:

  include Gem::UserInteraction

  include Gem::InstallerUninstallerUtils

  ##
  # The directory a gem's executables will be installed into

  attr_reader :bin_dir

  attr_reader :build_root # :nodoc:

  ##
  # The gem repository the gem will be installed into

  attr_reader :gem_home

  ##
  # The options passed when the Gem::Installer was instantiated.

  attr_reader :options

  ##
  # The gem package instance.

  attr_reader :package

  class << self
    #
    # Changes in rubygems to lazily loading `rubygems/command` (in order to
    # lazily load `optparse` as a side effect) affect bundler's custom installer
    # which uses `Gem::Command` without requiring it (up until bundler 2.2.29).
    # This hook is to compensate for that missing require.
    #
    # TODO: Remove when rubygems no longer supports running on bundler older
    # than 2.2.29.

    def inherited(klass)
      if klass.name == "Bundler::RubyGemsGemInstaller"
        require "rubygems/command"
      end

      super(klass)
    end

    ##
    # Overrides the executable format.
    #
    # This is a sprintf format with a "%s" which will be replaced with the
    # executable name.  It is based off the ruby executable name's difference
    # from "ruby".

    attr_writer :exec_format

    # Defaults to use Ruby's program prefix and suffix.
    def exec_format
      @exec_format ||= Gem.default_exec_format
    end
  end

  ##
  # Construct an installer object for the gem file located at +path+

  def self.at(path, options = {})
    security_policy = options[:security_policy]
    package = Gem::Package.new path, security_policy
    new package, options
  end

  class FakePackage
    attr_accessor :spec

    attr_accessor :dir_mode
    attr_accessor :prog_mode
    attr_accessor :data_mode

    def initialize(spec)
      @spec = spec
    end

    def extract_files(destination_dir, pattern = "*")
      FileUtils.mkdir_p destination_dir

      spec.files.each do |file|
        file = File.join destination_dir, file
        next if File.exist? file
        FileUtils.mkdir_p File.dirname(file)
        File.open file, "w" do |fp|
          fp.puts "# #{file}"
        end
      end
    end

    def copy_to(path)
    end
  end

  ##
  # Construct an installer object for an ephemeral gem (one where we don't
  # actually have a .gem file, just a spec)

  def self.for_spec(spec, options = {})
    # FIXME: we should have a real Package class for this
    new FakePackage.new(spec), options
  end

  ##
  # Constructs an Installer instance that will install the gem at +package+ which
  # can either be a path or an instance of Gem::Package.  +options+ is a Hash
  # with the following keys:
  #
  # :bin_dir:: Where to put a bin wrapper if needed.
  # :development:: Whether or not development dependencies should be installed.
  # :env_shebang:: Use /usr/bin/env in bin wrappers.
  # :force:: Overrides all version checks and security policy checks, except
  #          for a signed-gems-only policy.
  # :format_executable:: Format the executable the same as the Ruby executable.
  #                      If your Ruby is ruby18, foo_exec will be installed as
  #                      foo_exec18.
  # :ignore_dependencies:: Don't raise if a dependency is missing.
  # :install_dir:: The directory to install the gem into.
  # :security_policy:: Use the specified security policy.  See Gem::Security
  # :user_install:: Indicate that the gem should be unpacked into the users
  #                 personal gem directory.
  # :only_install_dir:: Only validate dependencies against what is in the
  #                     install_dir
  # :wrappers:: Install wrappers if true, symlinks if false.
  # :build_args:: An Array of arguments to pass to the extension builder
  #               process. If not set, then Gem::Command.build_args is used
  # :post_install_message:: Print gem post install message if true

  def initialize(package, options={})
    require "fileutils"

    @options = options
    @package = package

    process_options

    @package.dir_mode = options[:dir_mode]
    @package.prog_mode = options[:prog_mode]
    @package.data_mode = options[:data_mode]
  end

  ##
  # Checks if +filename+ exists in +@bin_dir+.
  #
  # If +@force+ is set +filename+ is overwritten.
  #
  # If +filename+ exists and it is a RubyGems wrapper for a different gem, then
  # the user is consulted.
  #
  # If +filename+ exists and +@bin_dir+ is Gem.default_bindir (/usr/local) the
  # user is consulted.
  #
  # Otherwise +filename+ is overwritten.

  def check_executable_overwrite(filename) # :nodoc:
    return if @force

    generated_bin = File.join @bin_dir, formatted_program_filename(filename)

    return unless File.exist? generated_bin

    ruby_executable = false
    existing = nil

    File.open generated_bin, "rb" do |io|
      line = io.gets
      shebang = /^#!.*ruby/o

      # TruffleRuby uses a bash prelude in default launchers
      if load_relative_enabled? || RUBY_ENGINE == "truffleruby"
        until line.nil? || shebang.match?(line) do
          line = io.gets
        end
      end

      next unless line&.match?(shebang)

      io.gets # blankline

      # TODO: detect a specially formatted comment instead of trying
      # to find a string inside Ruby code.
      next unless io.gets&.include?("This file was generated by RubyGems")

      ruby_executable = true
      existing = io.read.slice(/
          ^\s*(
            gem \s |
            load \s Gem\.bin_path\( |
            load \s Gem\.activate_bin_path\(
          )
          (['"])(.*?)(\2),
        /x, 3)
    end

    return if spec.name == existing

    # somebody has written to RubyGems' directory, overwrite, too bad
    return if Gem.default_bindir != @bin_dir && !ruby_executable

    question = "#{spec.name}'s executable \"#{filename}\" conflicts with ".dup

    if ruby_executable
      question << (existing || "an unknown executable")

      return if ask_yes_no "#{question}\nOverwrite the executable?", false

      conflict = "installed executable from #{existing}"
    else
      question << generated_bin

      return if ask_yes_no "#{question}\nOverwrite the executable?", false

      conflict = generated_bin
    end

    raise Gem::InstallError,
      "\"#{filename}\" from #{spec.name} conflicts with #{conflict}"
  end

  ##
  # Lazy accessor for the spec's gem directory.

  def gem_dir
    @gem_dir ||= File.join(gem_home, "gems", spec.full_name)
  end

  ##
  # Lazy accessor for the installer's spec.

  def spec
    @package.spec
  end

  ##
  # Installs the gem and returns a loaded Gem::Specification for the installed
  # gem.
  #
  # The gem will be installed with the following structure:
  #
  #   @gem_home/
  #     cache/<gem-version>.gem #=> a cached copy of the installed gem
  #     gems/<gem-version>/... #=> extracted files
  #     specifications/<gem-version>.gemspec #=> the Gem::Specification

  def install
    pre_install_checks

    run_pre_install_hooks

    # Set loaded_from to ensure extension_dir is correct
    if @options[:install_as_default]
      spec.loaded_from = default_spec_file
    else
      spec.loaded_from = spec_file
    end

    # Completely remove any previous gem files
    FileUtils.rm_rf gem_dir
    FileUtils.rm_rf spec.extension_dir

    dir_mode = options[:dir_mode]
    FileUtils.mkdir_p gem_dir, mode: dir_mode && 0o755

    if @options[:install_as_default]
      extract_bin
      write_default_spec
    else
      extract_files

      build_extensions
      write_build_info_file
      run_post_build_hooks
    end

    generate_bin
    generate_plugins

    unless @options[:install_as_default]
      write_spec
      write_cache_file
    end

    File.chmod(dir_mode, gem_dir) if dir_mode

    say spec.post_install_message if options[:post_install_message] && !spec.post_install_message.nil?

    Gem::Specification.add_spec(spec) unless @install_dir

    load_plugin

    run_post_install_hooks

    spec
  rescue Errno::EACCES => e
    # Permission denied - /path/to/foo
    raise Gem::FilePermissionError, e.message.split(" - ").last
  end

  def run_pre_install_hooks # :nodoc:
    Gem.pre_install_hooks.each do |hook|
      next unless hook.call(self) == false
      location = " at #{$1}" if hook.inspect =~ /[ @](.*:\d+)/

      message = "pre-install hook#{location} failed for #{spec.full_name}"
      raise Gem::InstallError, message
    end
  end

  def run_post_build_hooks # :nodoc:
    Gem.post_build_hooks.each do |hook|
      next unless hook.call(self) == false
      FileUtils.rm_rf gem_dir

      location = " at #{$1}" if hook.inspect =~ /[ @](.*:\d+)/

      message = "post-build hook#{location} failed for #{spec.full_name}"
      raise Gem::InstallError, message
    end
  end

  def run_post_install_hooks # :nodoc:
    Gem.post_install_hooks.each do |hook|
      hook.call self
    end
  end

  ##
  #
  # Return an Array of Specifications contained within the gem_home
  # we'll be installing into.

  def installed_specs
    @installed_specs ||= begin
      specs = []

      Gem::Util.glob_files_in_dir("*.gemspec", File.join(gem_home, "specifications")).each do |path|
        spec = Gem::Specification.load path
        specs << spec if spec
      end

      specs
    end
  end

  ##
  # Ensure that the dependency is satisfied by the current installation of
  # gem.  If it is not an exception is raised.
  #
  # spec       :: Gem::Specification
  # dependency :: Gem::Dependency

  def ensure_dependency(spec, dependency)
    unless installation_satisfies_dependency? dependency
      raise Gem::InstallError, "#{spec.name} requires #{dependency}"
    end
    true
  end

  ##
  # True if the gems in the system satisfy +dependency+.

  def installation_satisfies_dependency?(dependency)
    return true if @options[:development] && dependency.type == :development
    return true if installed_specs.detect {|s| dependency.matches_spec? s }
    return false if @only_install_dir
    !dependency.matching_specs.empty?
  end

  ##
  # Unpacks the gem into the given directory.

  def unpack(directory)
    @gem_dir = directory
    extract_files
  end
  rubygems_deprecate :unpack

  ##
  # The location of the spec file that is installed.
  #

  def spec_file
    File.join gem_home, "specifications", "#{spec.full_name}.gemspec"
  end

  ##
  # The location of the default spec file for default gems.
  #

  def default_spec_file
    File.join gem_home, "specifications", "default", "#{spec.full_name}.gemspec"
  end

  ##
  # Writes the .gemspec specification (in Ruby) to the gem home's
  # specifications directory.

  def write_spec
    spec.installed_by_version = Gem.rubygems_version

    Gem.write_binary(spec_file, spec.to_ruby_for_cache)
  end

  ##
  # Writes the full .gemspec specification (in Ruby) to the gem home's
  # specifications/default directory.
  #
  # In contrast to #write_spec, this keeps file lists, so the `gem contents`
  # command works.

  def write_default_spec
    Gem.write_binary(default_spec_file, spec.to_ruby)
  end

  ##
  # Creates windows .bat files for easy running of commands

  def generate_windows_script(filename, bindir)
    if Gem.win_platform?
      script_name = formatted_program_filename(filename) + ".bat"
      script_path = File.join bindir, File.basename(script_name)
      File.open script_path, "w" do |file|
        file.puts windows_stub_script(bindir, filename)
      end

      verbose script_path
    end
  end

  def generate_bin # :nodoc:
    executables = spec.executables
    return if executables.nil? || executables.empty?

    if @gem_home == Gem.user_dir
      # If we get here, then one of the following likely happened:
      # - `--user-install` was specified
      # - `Gem::PathSupport#home` fell back to `Gem.user_dir`
      # - GEM_HOME was manually set to `Gem.user_dir`

      check_that_user_bin_dir_is_in_path(executables)
    end

    ensure_writable_dir @bin_dir

    executables.each do |filename|
      bin_path = File.join gem_dir, spec.bindir, filename
      next unless File.exist? bin_path

      mode = File.stat(bin_path).mode
      dir_mode = options[:prog_mode] || (mode | 0o111)

      unless dir_mode == mode
        File.chmod dir_mode, bin_path
      end

      check_executable_overwrite filename

      if @wrappers
        generate_bin_script filename, @bin_dir
      else
        generate_bin_symlink filename, @bin_dir
      end
    end
  end

  def generate_plugins # :nodoc:
    latest = Gem::Specification.latest_spec_for(spec.name)
    return if latest && latest.version > spec.version

    ensure_writable_dir @plugins_dir

    if spec.plugins.empty?
      remove_plugins_for(spec, @plugins_dir)
    else
      regenerate_plugins_for(spec, @plugins_dir)
    end
  rescue ArgumentError => e
    raise e, "#{latest.name} #{latest.version} #{spec.name} #{spec.version}: #{e.message}"
  end

  ##
  # Creates the scripts to run the applications in the gem.
  #--
  # The Windows script is generated in addition to the regular one due to a
  # bug or misfeature in the Windows shell's pipe.  See
  # https://blade.ruby-lang.org/ruby-talk/193379

  def generate_bin_script(filename, bindir)
    bin_script_path = File.join bindir, formatted_program_filename(filename)

    Gem.open_file_with_lock(bin_script_path) do
      require "fileutils"
      FileUtils.rm_f bin_script_path # prior install may have been --no-wrappers

      File.open(bin_script_path, "wb", 0o755) do |file|
        file.write app_script_text(filename)
        file.chmod(options[:prog_mode] || 0o755)
      end
    end

    verbose bin_script_path

    generate_windows_script filename, bindir
  end

  ##
  # Creates the symlinks to run the applications in the gem.  Moves
  # the symlink if the gem being installed has a newer version.

  def generate_bin_symlink(filename, bindir)
    src = File.join gem_dir, spec.bindir, filename
    dst = File.join bindir, formatted_program_filename(filename)

    if File.exist? dst
      if File.symlink? dst
        link = File.readlink(dst).split File::SEPARATOR
        cur_version = Gem::Version.create(link[-3].sub(/^.*-/, ""))
        return if spec.version < cur_version
      end
      File.unlink dst
    end

    FileUtils.symlink src, dst, verbose: Gem.configuration.really_verbose
  rescue NotImplementedError, SystemCallError
    alert_warning "Unable to use symlinks, installing wrapper"
    generate_bin_script filename, bindir
  end

  ##
  # Generates a #! line for +bin_file_name+'s wrapper copying arguments if
  # necessary.
  #
  # If the :custom_shebang config is set, then it is used as a template
  # for how to create the shebang used for to run a gem's executables.
  #
  # The template supports 4 expansions:
  #
  #  $env    the path to the unix env utility
  #  $ruby   the path to the currently running ruby interpreter
  #  $exec   the path to the gem's executable
  #  $name   the name of the gem the executable is for
  #

  def shebang(bin_file_name)
    path = File.join gem_dir, spec.bindir, bin_file_name
    first_line = File.open(path, "rb", &:gets) || ""

    if first_line.start_with?("#!")
      # Preserve extra words on shebang line, like "-w".  Thanks RPA.
      shebang = first_line.sub(/\A\#!.*?ruby\S*((\s+\S+)+)/, "#!#{Gem.ruby}")
      opts = $1
      shebang.strip! # Avoid nasty ^M issues.
    end

    if which = Gem.configuration[:custom_shebang]
      # replace bin_file_name with "ruby" to avoid endless loops
      which = which.gsub(/ #{bin_file_name}$/," #{ruby_install_name}")

      which = which.gsub(/\$(\w+)/) do
        case $1
        when "env"
          @env_path ||= ENV_PATHS.find {|env_path| File.executable? env_path }
        when "ruby"
          "#{Gem.ruby}#{opts}"
        when "exec"
          bin_file_name
        when "name"
          spec.name
        end
      end

      "#!#{which}"
    elsif @env_shebang
      # Create a plain shebang line.
      @env_path ||= ENV_PATHS.find {|env_path| File.executable? env_path }
      "#!#{@env_path} #{ruby_install_name}"
    else
      "#{bash_prolog_script}#!#{Gem.ruby}#{opts}"
    end
  end

  ##
  # Ensures the Gem::Specification written out for this gem is loadable upon
  # installation.

  def ensure_loadable_spec
    ruby = spec.to_ruby_for_cache

    begin
      eval ruby
    rescue StandardError, SyntaxError => e
      raise Gem::InstallError,
            "The specification for #{spec.full_name} is corrupt (#{e.class})"
    end
  end

  def ensure_dependencies_met # :nodoc:
    deps = spec.runtime_dependencies
    deps |= spec.development_dependencies if @development

    deps.each do |dep_gem|
      ensure_dependency spec, dep_gem
    end
  end

  def process_options # :nodoc:
    @options = {
      bin_dir: nil,
      env_shebang: false,
      force: false,
      only_install_dir: false,
      post_install_message: true,
    }.merge options

    @env_shebang         = options[:env_shebang]
    @force               = options[:force]
    @install_dir         = options[:install_dir]
    @user_install        = options[:user_install]
    @ignore_dependencies = options[:ignore_dependencies]
    @format_executable   = options[:format_executable]
    @wrappers            = options[:wrappers]
    @only_install_dir    = options[:only_install_dir]

    @bin_dir             = options[:bin_dir]
    @development         = options[:development]
    @build_root          = options[:build_root]

    @build_args = options[:build_args]

    @gem_home = @install_dir || user_install_dir || Gem.dir

    # If the user has asked for the gem to be installed in a directory that is
    # the system gem directory, then use the system bin directory, else create
    # (or use) a new bin dir under the gem_home.
    @bin_dir ||= Gem.bindir(@gem_home)

    @plugins_dir = Gem.plugindir(@gem_home)

    unless @build_root.nil?
      @bin_dir = File.join(@build_root, @bin_dir.gsub(/^[a-zA-Z]:/, ""))
      @gem_home = File.join(@build_root, @gem_home.gsub(/^[a-zA-Z]:/, ""))
      @plugins_dir = File.join(@build_root, @plugins_dir.gsub(/^[a-zA-Z]:/, ""))
      alert_warning "You build with buildroot.\n  Build root: #{@build_root}\n  Bin dir: #{@bin_dir}\n  Gem home: #{@gem_home}\n  Plugins dir: #{@plugins_dir}"
    end
  end

  def check_that_user_bin_dir_is_in_path(executables) # :nodoc:
    user_bin_dir = @bin_dir || Gem.bindir(gem_home)
    user_bin_dir = user_bin_dir.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR

    path = ENV["PATH"]
    path = path.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR

    if Gem.win_platform?
      path = path.downcase
      user_bin_dir = user_bin_dir.downcase
    end

    path = path.split(File::PATH_SEPARATOR)

    unless path.include? user_bin_dir
      unless !Gem.win_platform? && (path.include? user_bin_dir.sub(ENV["HOME"], "~"))
        alert_warning "You don't have #{user_bin_dir} in your PATH,\n\t  gem executables (#{executables.join(", ")}) will not run."
      end
    end
  end

  def verify_gem_home # :nodoc:
    FileUtils.mkdir_p gem_home, mode: options[:dir_mode] && 0o755
  end

  def verify_spec
    unless Gem::Specification::VALID_NAME_PATTERN.match?(spec.name)
      raise Gem::InstallError, "#{spec} has an invalid name"
    end

    if spec.raw_require_paths.any? {|path| path =~ /\R/ }
      raise Gem::InstallError, "#{spec} has an invalid require_paths"
    end

    if spec.extensions.any? {|ext| ext =~ /\R/ }
      raise Gem::InstallError, "#{spec} has an invalid extensions"
    end

    if /\R/.match?(spec.platform.to_s)
      raise Gem::InstallError, "#{spec.platform} is an invalid platform"
    end

    unless /\A\d+\z/.match?(spec.specification_version.to_s)
      raise Gem::InstallError, "#{spec} has an invalid specification_version"
    end

    if spec.dependencies.any? {|dep| dep.type != :runtime && dep.type != :development }
      raise Gem::InstallError, "#{spec} has an invalid dependencies"
    end

    if spec.dependencies.any? {|dep| dep.name =~ /(?:\R|[<>])/ }
      raise Gem::InstallError, "#{spec} has an invalid dependencies"
    end
  end

  ##
  # Return the text for an application file.

  def app_script_text(bin_file_name)
    # NOTE: that the `load` lines cannot be indented, as old RG versions match
    # against the beginning of the line
    <<-TEXT
#{shebang bin_file_name}
#
# This file was generated by RubyGems.
#
# The application '#{spec.name}' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'
#{gemdeps_load(spec.name)}
version = "#{Gem::Requirement.default_prerelease}"

str = ARGV.first
if str
  str = str.b[/\\A_(.*)_\\z/, 1]
  if str and Gem::Version.correct?(str)
    #{explicit_version_requirement(spec.name)}
    ARGV.shift
  end
end

if Gem.respond_to?(:activate_bin_path)
load Gem.activate_bin_path('#{spec.name}', '#{bin_file_name}', version)
else
gem #{spec.name.dump}, version
load Gem.bin_path(#{spec.name.dump}, #{bin_file_name.dump}, version)
end
TEXT
  end

  def gemdeps_load(name)
    return "" if name == "bundler"

    <<-TEXT

Gem.use_gemdeps
TEXT
  end

  def explicit_version_requirement(name)
    code = "version = str"
    return code unless name == "bundler"

    code += <<-TEXT

    ENV['BUNDLER_VERSION'] = str
TEXT
  end

  ##
  # return the stub script text used to launch the true Ruby script

  def windows_stub_script(bindir, bin_file_name)
    rb_topdir = RbConfig::TOPDIR || File.dirname(rb_config["bindir"])

    # get ruby executable file name from RbConfig
    ruby_exe = "#{rb_config["RUBY_INSTALL_NAME"]}#{rb_config["EXEEXT"]}"
    ruby_exe = "ruby.exe" if ruby_exe.empty?

    if File.exist?(File.join(bindir, ruby_exe))
      # stub & ruby.exe within same folder.  Portable
      <<-TEXT
@ECHO OFF
@"%~dp0#{ruby_exe}" "%~dpn0" %*
      TEXT
    elsif bindir.downcase.start_with? rb_topdir.downcase
      # stub within ruby folder, but not standard bin.  Portable
      require "pathname"
      from = Pathname.new bindir
      to   = Pathname.new "#{rb_topdir}/bin"
      rel  = to.relative_path_from from
      <<-TEXT
@ECHO OFF
@"%~dp0#{rel}/#{ruby_exe}" "%~dpn0" %*
      TEXT
    else
      # outside ruby folder, maybe -user-install or bundler.  Portable, but ruby
      # is dependent on PATH
      <<-TEXT
@ECHO OFF
@#{ruby_exe} "%~dpn0" %*
      TEXT
    end
  end
  ##
  # Builds extensions.  Valid types of extensions are extconf.rb files,
  # configure scripts and rakefiles or mkrf_conf files.

  def build_extensions
    builder = Gem::Ext::Builder.new spec, build_args

    builder.build_extensions
  end

  ##
  # Reads the file index and extracts each file into the gem directory.
  #
  # Ensures that files can't be installed outside the gem directory.

  def extract_files
    @package.extract_files gem_dir
  end

  ##
  # Extracts only the bin/ files from the gem into the gem directory.
  # This is used by default gems to allow a gem-aware stub to function
  # without the full gem installed.

  def extract_bin
    @package.extract_files gem_dir, "#{spec.bindir}/*"
  end

  ##
  # Prefix and suffix the program filename the same as ruby.

  def formatted_program_filename(filename)
    if @format_executable
      self.class.exec_format % File.basename(filename)
    else
      filename
    end
  end

  ##
  #
  # Return the target directory where the gem is to be installed. This
  # directory is not guaranteed to be populated.
  #

  def dir
    gem_dir.to_s
  end

  ##
  # Filename of the gem being installed.

  def gem
    @package.gem.path
  end

  ##
  # Performs various checks before installing the gem such as the install
  # repository is writable and its directories exist, required Ruby and
  # rubygems versions are met and that dependencies are installed.
  #
  # Version and dependency checks are skipped if this install is forced.
  #
  # The dependent check will be skipped if the install is ignoring dependencies.

  def pre_install_checks
    verify_gem_home

    # The name and require_paths must be verified first, since it could contain
    # ruby code that would be eval'ed in #ensure_loadable_spec
    verify_spec

    ensure_loadable_spec

    if options[:install_as_default]
      Gem.ensure_default_gem_subdirectories gem_home
    else
      Gem.ensure_gem_subdirectories gem_home
    end

    return true if @force

    ensure_dependencies_met unless @ignore_dependencies

    true
  end

  ##
  # Writes the file containing the arguments for building this gem's
  # extensions.

  def write_build_info_file
    return if build_args.empty?

    build_info_dir = File.join gem_home, "build_info"

    dir_mode = options[:dir_mode]
    FileUtils.mkdir_p build_info_dir, mode: dir_mode && 0o755

    build_info_file = File.join build_info_dir, "#{spec.full_name}.info"

    File.open build_info_file, "w" do |io|
      build_args.each do |arg|
        io.puts arg
      end
    end

    File.chmod(dir_mode, build_info_dir) if dir_mode
  end

  ##
  # Writes the .gem file to the cache directory

  def write_cache_file
    cache_file = File.join gem_home, "cache", spec.file_name
    @package.copy_to cache_file
  end

  def ensure_writable_dir(dir) # :nodoc:
    begin
      Dir.mkdir dir, *[options[:dir_mode] && 0o755].compact
    rescue SystemCallError
      raise unless File.directory? dir
    end

    raise Gem::FilePermissionError.new(dir) unless File.writable? dir
  end

  private

  def user_install_dir
    # never install to user home in --build-root mode
    return unless @build_root.nil?

    # Please note that @user_install might have three states:
    # * `true`: `--user-install`
    # * `false`: `--no-user-install` and
    # * `nil`: option was not specified
    if @user_install || (@user_install.nil? && Gem.default_user_install)
      Gem.user_dir
    end
  end

  def build_args
    @build_args ||= begin
                      require_relative "command"
                      Gem::Command.build_args
                    end
  end

  def rb_config
    RbConfig::CONFIG
  end

  def ruby_install_name
    rb_config["ruby_install_name"]
  end

  def load_relative_enabled?
    rb_config["LIBRUBY_RELATIVE"] == "yes"
  end

  def bash_prolog_script
    if load_relative_enabled?
      script = +<<~EOS
        bindir="${0%/*}"
      EOS

      script << %(exec "$bindir/#{ruby_install_name}" "-x" "$0" "$@"\n)

      <<~EOS
        #!/bin/sh
        # -*- ruby -*-
        _=_\\
        =begin
        #{script.chomp}
        =end
      EOS
    else
      ""
    end
  end

  def load_plugin
    specs = Gem::Specification.find_all_by_name(spec.name)
    # If old version already exists, this plugin isn't loaded
    # immediately. It's for avoiding a case that multiple versions
    # are loaded at the same time.
    return unless specs.size == 1

    plugin_files = spec.plugins.map do |plugin|
      File.join(@plugins_dir, "#{spec.name}_plugin#{File.extname(plugin)}")
    end
    Gem.load_plugin_files(plugin_files)
  end
end
