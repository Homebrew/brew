# frozen_string_literal: true

require_relative "bundler/vendored_fileutils"
require "pathname"
require "rbconfig"

require_relative "bundler/errors"
require_relative "bundler/environment_preserver"
require_relative "bundler/plugin"
require_relative "bundler/rubygems_ext"
require_relative "bundler/rubygems_integration"
require_relative "bundler/version"
require_relative "bundler/constants"
require_relative "bundler/current_ruby"
require_relative "bundler/build_metadata"

# Bundler provides a consistent environment for Ruby projects by
# tracking and installing the exact gems and versions that are needed.
#
# Bundler is a part of Ruby's standard library.
#
# Bundler is used by creating _gemfiles_ listing all the project dependencies
# and (optionally) their versions and then using
#
#   require 'bundler/setup'
#
# or Bundler.setup to setup environment where only specified gems and their
# specified versions could be used.
#
# See {Bundler website}[https://bundler.io/docs.html] for extensive documentation
# on gemfiles creation and Bundler usage.
#
# As a standard library inside project, Bundler could be used for introspection
# of loaded and required modules.
#
module Bundler
  environment_preserver = EnvironmentPreserver.from_env
  ORIGINAL_ENV = environment_preserver.restore
  environment_preserver.replace_with_backup
  SUDO_MUTEX = Thread::Mutex.new

  autoload :Checksum,               File.expand_path("bundler/checksum", __dir__)
  autoload :CLI,                    File.expand_path("bundler/cli", __dir__)
  autoload :CIDetector,             File.expand_path("bundler/ci_detector", __dir__)
  autoload :CompactIndexClient,     File.expand_path("bundler/compact_index_client", __dir__)
  autoload :Definition,             File.expand_path("bundler/definition", __dir__)
  autoload :Dependency,             File.expand_path("bundler/dependency", __dir__)
  autoload :Deprecate,              File.expand_path("bundler/deprecate", __dir__)
  autoload :Digest,                 File.expand_path("bundler/digest", __dir__)
  autoload :Dsl,                    File.expand_path("bundler/dsl", __dir__)
  autoload :EndpointSpecification,  File.expand_path("bundler/endpoint_specification", __dir__)
  autoload :Env,                    File.expand_path("bundler/env", __dir__)
  autoload :Fetcher,                File.expand_path("bundler/fetcher", __dir__)
  autoload :FeatureFlag,            File.expand_path("bundler/feature_flag", __dir__)
  autoload :GemHelper,              File.expand_path("bundler/gem_helper", __dir__)
  autoload :GemHelpers,             File.expand_path("bundler/gem_helpers", __dir__)
  autoload :GemVersionPromoter,     File.expand_path("bundler/gem_version_promoter", __dir__)
  autoload :Graph,                  File.expand_path("bundler/graph", __dir__)
  autoload :Index,                  File.expand_path("bundler/index", __dir__)
  autoload :Injector,               File.expand_path("bundler/injector", __dir__)
  autoload :Installer,              File.expand_path("bundler/installer", __dir__)
  autoload :LazySpecification,      File.expand_path("bundler/lazy_specification", __dir__)
  autoload :LockfileParser,         File.expand_path("bundler/lockfile_parser", __dir__)
  autoload :MatchRemoteMetadata,    File.expand_path("bundler/match_remote_metadata", __dir__)
  autoload :ProcessLock,            File.expand_path("bundler/process_lock", __dir__)
  autoload :RemoteSpecification,    File.expand_path("bundler/remote_specification", __dir__)
  autoload :Resolver,               File.expand_path("bundler/resolver", __dir__)
  autoload :Retry,                  File.expand_path("bundler/retry", __dir__)
  autoload :RubyDsl,                File.expand_path("bundler/ruby_dsl", __dir__)
  autoload :RubyVersion,            File.expand_path("bundler/ruby_version", __dir__)
  autoload :Runtime,                File.expand_path("bundler/runtime", __dir__)
  autoload :SelfManager,            File.expand_path("bundler/self_manager", __dir__)
  autoload :Settings,               File.expand_path("bundler/settings", __dir__)
  autoload :SharedHelpers,          File.expand_path("bundler/shared_helpers", __dir__)
  autoload :Source,                 File.expand_path("bundler/source", __dir__)
  autoload :SourceList,             File.expand_path("bundler/source_list", __dir__)
  autoload :SourceMap,              File.expand_path("bundler/source_map", __dir__)
  autoload :SpecSet,                File.expand_path("bundler/spec_set", __dir__)
  autoload :StubSpecification,      File.expand_path("bundler/stub_specification", __dir__)
  autoload :UI,                     File.expand_path("bundler/ui", __dir__)
  autoload :URICredentialsFilter,   File.expand_path("bundler/uri_credentials_filter", __dir__)
  autoload :URINormalizer,          File.expand_path("bundler/uri_normalizer", __dir__)
  autoload :SafeMarshal,            File.expand_path("bundler/safe_marshal", __dir__)

  class << self
    def configure
      @configure ||= configure_gem_home_and_path
    end

    def ui
      (defined?(@ui) && @ui) || (self.ui = UI::Shell.new)
    end

    def ui=(ui)
      Bundler.rubygems.ui = UI::RGProxy.new(ui)
      @ui = ui
    end

    # Returns absolute path of where gems are installed on the filesystem.
    def bundle_path
      @bundle_path ||= Pathname.new(configured_bundle_path.path).expand_path(root)
    end

    def create_bundle_path
      mkdir_p(bundle_path) unless bundle_path.exist?

      @bundle_path = bundle_path.realpath
    rescue Errno::EEXIST
      raise PathError, "Could not install to path `#{bundle_path}` " \
        "because a file already exists at that path. Either remove or rename the file so the directory can be created."
    end

    def configured_bundle_path
      @configured_bundle_path ||= settings.path.tap(&:validate!)
    end

    # Returns absolute location of where binstubs are installed to.
    def bin_path
      @bin_path ||= begin
        path = settings[:bin] || "bin"
        path = Pathname.new(path).expand_path(root).expand_path
        mkdir_p(path)
        path
      end
    end

    # Turns on the Bundler runtime. After +Bundler.setup+ call, all +load+ or
    # +require+ of the gems would be allowed only if they are part of
    # the Gemfile or Ruby's standard library. If the versions specified
    # in Gemfile, only those versions would be loaded.
    #
    # Assuming Gemfile
    #
    #    gem 'first_gem', '= 1.0'
    #    group :test do
    #      gem 'second_gem', '= 1.0'
    #    end
    #
    # The code using Bundler.setup works as follows:
    #
    #    require 'third_gem' # allowed, required from global gems
    #    require 'first_gem' # allowed, loads the last installed version
    #    Bundler.setup
    #    require 'fourth_gem' # fails with LoadError
    #    require 'second_gem' # loads exactly version 1.0
    #
    # +Bundler.setup+ can be called only once, all subsequent calls are no-op.
    #
    # If _groups_ list is provided, only gems from specified groups would
    # be allowed (gems specified outside groups belong to special +:default+ group).
    #
    # To require all gems from Gemfile (or only some groups), see Bundler.require.
    #
    def setup(*groups)
      # Return if all groups are already loaded
      return @setup if defined?(@setup) && @setup

      definition.validate_runtime!

      SharedHelpers.print_major_deprecations!

      if groups.empty?
        # Load all groups, but only once
        @setup = load.setup
      else
        load.setup(*groups)
      end
    end

    def auto_switch
      self_manager.restart_with_locked_bundler_if_needed
    end

    # Automatically install dependencies if Bundler.settings[:auto_install] exists.
    # This is set through config cmd `bundle config set --global auto_install 1`.
    #
    # Note that this method `nil`s out the global Definition object, so it
    # should be called first, before you instantiate anything like an
    # `Installer` that'll keep a reference to the old one instead.
    def auto_install
      return unless settings[:auto_install]

      begin
        definition.specs
      rescue GemNotFound, GitError
        ui.info "Automatically installing missing gems."
        reset!
        CLI::Install.new({}).run
        reset!
      end
    end

    # Setups Bundler environment (see Bundler.setup) if it is not already set,
    # and loads all gems from groups specified. Unlike ::setup, can be called
    # multiple times with different groups (if they were allowed by setup).
    #
    # Assuming Gemfile
    #
    #    gem 'first_gem', '= 1.0'
    #    group :test do
    #      gem 'second_gem', '= 1.0'
    #    end
    #
    # The code will work as follows:
    #
    #    Bundler.setup # allow all groups
    #    Bundler.require(:default) # requires only first_gem
    #    # ...later
    #    Bundler.require(:test)   # requires second_gem
    #
    def require(*groups)
      setup(*groups).require(*groups)
    end

    def load
      @load ||= Runtime.new(root, definition)
    end

    def environment
      SharedHelpers.major_deprecation 2, "Bundler.environment has been removed in favor of Bundler.load", print_caller_location: true
      load
    end

    # Returns an instance of Bundler::Definition for given Gemfile and lockfile
    #
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @param lockfile [Pathname] Path to Gemfile.lock
    # @return [Bundler::Definition]
    def definition(unlock = nil, lockfile = default_lockfile)
      @definition = nil if unlock
      @definition ||= begin
        configure
        Definition.build(default_gemfile, lockfile, unlock)
      end
    end

    def frozen_bundle?
      frozen = settings[:frozen]
      return frozen unless frozen.nil?

      settings[:deployment]
    end

    def locked_gems
      @locked_gems ||=
        if defined?(@definition) && @definition
          definition.locked_gems
        elsif Bundler.default_lockfile.file?
          lock = Bundler.read_file(Bundler.default_lockfile)
          LockfileParser.new(lock)
        end
    end

    def most_specific_locked_platform?(platform)
      return false unless defined?(@definition) && @definition

      definition.most_specific_locked_platform == platform
    end

    def ruby_scope
      "#{Bundler.rubygems.ruby_engine}/#{RbConfig::CONFIG["ruby_version"]}"
    end

    def user_home
      @user_home ||= begin
        home = Bundler.rubygems.user_home
        bundle_home = home ? File.join(home, ".bundle") : nil

        warning = if home.nil?
          "Your home directory is not set."
        elsif !File.directory?(home)
          "`#{home}` is not a directory."
        elsif !File.writable?(home) && (!File.directory?(bundle_home) || !File.writable?(bundle_home))
          "`#{home}` is not writable."
        end

        if warning
          Bundler.ui.warn "#{warning}\n"
          user_home = tmp_home_path
          Bundler.ui.warn "Bundler will use `#{user_home}' as your home directory temporarily.\n"
          user_home
        else
          Pathname.new(home)
        end
      end
    end

    def user_bundle_path(dir = "home")
      env_var, fallback = case dir
                          when "home"
                            ["BUNDLE_USER_HOME", proc { Pathname.new(user_home).join(".bundle") }]
                          when "cache"
                            ["BUNDLE_USER_CACHE", proc { user_bundle_path.join("cache") }]
                          when "config"
                            ["BUNDLE_USER_CONFIG", proc { user_bundle_path.join("config") }]
                          when "plugin"
                            ["BUNDLE_USER_PLUGIN", proc { user_bundle_path.join("plugin") }]
                          else
                            raise BundlerError, "Unknown user path requested: #{dir}"
      end
      # `fallback` will already be a Pathname, but Pathname.new() is
      # idempotent so it's OK
      Pathname.new(ENV.fetch(env_var, &fallback))
    end

    def user_cache
      user_bundle_path("cache")
    end

    def home
      bundle_path.join("bundler")
    end

    def install_path
      home.join("gems")
    end

    def specs_path
      bundle_path.join("specifications")
    end

    def root
      @root ||= begin
                  SharedHelpers.root
                rescue GemfileNotFound
                  bundle_dir = default_bundle_dir
                  raise GemfileNotFound, "Could not locate Gemfile or .bundle/ directory" unless bundle_dir
                  Pathname.new(File.expand_path("..", bundle_dir))
                end
    end

    def app_config_path
      if app_config = ENV["BUNDLE_APP_CONFIG"]
        app_config_pathname = Pathname.new(app_config)

        if app_config_pathname.absolute?
          app_config_pathname
        else
          app_config_pathname.expand_path(root)
        end
      else
        root.join(".bundle")
      end
    end

    def app_cache(custom_path = nil)
      path = custom_path || root
      Pathname.new(path).join(settings.app_cache_path)
    end

    def tmp(name = Process.pid.to_s)
      Kernel.send(:require, "tmpdir")
      Pathname.new(Dir.mktmpdir(["bundler", name]))
    end

    def rm_rf(path)
      FileUtils.remove_entry_secure(path) if path && File.exist?(path)
    end

    def settings
      @settings ||= Settings.new(app_config_path)
    rescue GemfileNotFound
      @settings = Settings.new
    end

    # @return [Hash] Environment present before Bundler was activated
    def original_env
      ORIGINAL_ENV.clone
    end

    # @deprecated Use `unbundled_env` instead
    def clean_env
      message =
        "`Bundler.clean_env` has been deprecated in favor of `Bundler.unbundled_env`. " \
        "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env`"
      removed_message =
        "`Bundler.clean_env` has been removed in favor of `Bundler.unbundled_env`. " \
        "If you instead want the environment before bundler was originally loaded, use `Bundler.original_env`"
      Bundler::SharedHelpers.major_deprecation(2, message, removed_message: removed_message, print_caller_location: true)
      unbundled_env
    end

    # @return [Hash] Environment with all bundler-related variables removed
    def unbundled_env
      unbundle_env(original_env)
    end

    # Remove all bundler-related variables from ENV
    def unbundle_env!
      ENV.replace(unbundle_env(ENV))
    end

    # Run block with environment present before Bundler was activated
    def with_original_env
      with_env(original_env) { yield }
    end

    # @deprecated Use `with_unbundled_env` instead
    def with_clean_env
      message =
        "`Bundler.with_clean_env` has been deprecated in favor of `Bundler.with_unbundled_env`. " \
        "If you instead want the environment before bundler was originally loaded, use `Bundler.with_original_env`"
      removed_message =
        "`Bundler.with_clean_env` has been removed in favor of `Bundler.with_unbundled_env`. " \
        "If you instead want the environment before bundler was originally loaded, use `Bundler.with_original_env`"
      Bundler::SharedHelpers.major_deprecation(2, message, removed_message: removed_message, print_caller_location: true)
      with_env(unbundled_env) { yield }
    end

    # Run block with all bundler-related variables removed
    def with_unbundled_env
      with_env(unbundled_env) { yield }
    end

    # Run subcommand with the environment present before Bundler was activated
    def original_system(*args)
      with_original_env { Kernel.system(*args) }
    end

    # @deprecated Use `unbundled_system` instead
    def clean_system(*args)
      message =
        "`Bundler.clean_system` has been deprecated in favor of `Bundler.unbundled_system`. " \
        "If you instead want to run the command in the environment before bundler was originally loaded, use `Bundler.original_system`"
      removed_message =
        "`Bundler.clean_system` has been removed in favor of `Bundler.unbundled_system`. " \
        "If you instead want to run the command in the environment before bundler was originally loaded, use `Bundler.original_system`"
      Bundler::SharedHelpers.major_deprecation(2, message, removed_message: removed_message, print_caller_location: true)
      with_env(unbundled_env) { Kernel.system(*args) }
    end

    # Run subcommand in an environment with all bundler related variables removed
    def unbundled_system(*args)
      with_unbundled_env { Kernel.system(*args) }
    end

    # Run a `Kernel.exec` to a subcommand with the environment present before Bundler was activated
    def original_exec(*args)
      with_original_env { Kernel.exec(*args) }
    end

    # @deprecated Use `unbundled_exec` instead
    def clean_exec(*args)
      message =
        "`Bundler.clean_exec` has been deprecated in favor of `Bundler.unbundled_exec`. " \
        "If you instead want to exec to a command in the environment before bundler was originally loaded, use `Bundler.original_exec`"
      removed_message =
        "`Bundler.clean_exec` has been removed in favor of `Bundler.unbundled_exec`. " \
        "If you instead want to exec to a command in the environment before bundler was originally loaded, use `Bundler.original_exec`"
      Bundler::SharedHelpers.major_deprecation(2, message, removed_message: removed_message, print_caller_location: true)
      with_env(unbundled_env) { Kernel.exec(*args) }
    end

    # Run a `Kernel.exec` to a subcommand in an environment with all bundler related variables removed
    def unbundled_exec(*args)
      with_env(unbundled_env) { Kernel.exec(*args) }
    end

    def local_platform
      return Gem::Platform::RUBY if settings[:force_ruby_platform]
      Gem::Platform.local
    end

    def default_gemfile
      SharedHelpers.default_gemfile
    end

    def default_lockfile
      SharedHelpers.default_lockfile
    end

    def default_bundle_dir
      SharedHelpers.default_bundle_dir
    end

    def system_bindir
      # Gem.bindir doesn't always return the location that RubyGems will install
      # system binaries. If you put '-n foo' in your .gemrc, RubyGems will
      # install binstubs there instead. Unfortunately, RubyGems doesn't expose
      # that directory at all, so rather than parse .gemrc ourselves, we allow
      # the directory to be set as well, via `bundle config set --local bindir foo`.
      Bundler.settings[:system_bindir] || Bundler.rubygems.gem_bindir
    end

    def preferred_gemfile_name
      Bundler.settings[:init_gems_rb] ? "gems.rb" : "Gemfile"
    end

    def use_system_gems?
      configured_bundle_path.use_system_gems?
    end

    def mkdir_p(path)
      SharedHelpers.filesystem_access(path, :write) do |p|
        FileUtils.mkdir_p(p)
      end
    end

    def which(executable)
      if File.file?(executable) && File.executable?(executable)
        executable
      elsif paths = ENV["PATH"]
        quote = '"'
        paths.split(File::PATH_SEPARATOR).find do |path|
          path = path[1..-2] if path.start_with?(quote) && path.end_with?(quote)
          executable_path = File.expand_path(executable, path)
          return executable_path if File.file?(executable_path) && File.executable?(executable_path)
        end
      end
    end

    def read_file(file)
      SharedHelpers.filesystem_access(file, :read) do
        File.open(file, "r:UTF-8", &:read)
      end
    end

    def safe_load_marshal(data)
      if Gem.respond_to?(:load_safe_marshal)
        Gem.load_safe_marshal
        begin
          Gem::SafeMarshal.safe_load(data)
        rescue Gem::SafeMarshal::Reader::Error, Gem::SafeMarshal::Visitors::ToRuby::Error => e
          raise MarshalError, "#{e.class}: #{e.message}"
        end
      else
        load_marshal(data, marshal_proc: SafeMarshal.proc)
      end
    end

    def load_gemspec(file, validate = false)
      @gemspec_cache ||= {}
      key = File.expand_path(file)
      @gemspec_cache[key] ||= load_gemspec_uncached(file, validate)
      # Protect against caching side-effected gemspecs by returning a
      # new instance each time.
      @gemspec_cache[key]&.dup
    end

    def load_gemspec_uncached(file, validate = false)
      path = Pathname.new(file)
      contents = read_file(file)
      spec = if contents.start_with?("---") # YAML header
        eval_yaml_gemspec(path, contents)
      else
        # Eval the gemspec from its parent directory, because some gemspecs
        # depend on "./" relative paths.
        SharedHelpers.chdir(path.dirname.to_s) do
          eval_gemspec(path, contents)
        end
      end
      return unless spec
      spec.loaded_from = path.expand_path.to_s
      Bundler.rubygems.validate(spec) if validate
      spec
    end

    def clear_gemspec_cache
      @gemspec_cache = {}
    end

    def git_present?
      return @git_present if defined?(@git_present)
      @git_present = Bundler.which("git#{RbConfig::CONFIG["EXEEXT"]}")
    end

    def feature_flag
      @feature_flag ||= FeatureFlag.new(VERSION)
    end

    def reset!
      reset_paths!
      Plugin.reset!
      reset_rubygems!
    end

    def reset_settings_and_root!
      @settings = nil
      @root = nil
    end

    def reset_paths!
      @bin_path = nil
      @bundler_major_version = nil
      @bundle_path = nil
      @configure = nil
      @configured_bundle_path = nil
      @definition = nil
      @load = nil
      @locked_gems = nil
      @root = nil
      @settings = nil
      @setup = nil
      @user_home = nil
    end

    def reset_rubygems!
      return unless defined?(@rubygems) && @rubygems
      rubygems.undo_replacements
      rubygems.reset
      @rubygems = nil
    end

    def configure_gem_home_and_path(path = bundle_path)
      configure_gem_path
      configure_gem_home(path)
      Bundler.rubygems.clear_paths
    end

    def self_manager
      @self_manager ||= begin
                          require_relative "bundler/self_manager"
                          Bundler::SelfManager.new
                        end
    end

    private

    def unbundle_env(env)
      if env.key?("BUNDLER_ORIG_MANPATH")
        env["MANPATH"] = env["BUNDLER_ORIG_MANPATH"]
      end

      env.delete_if {|k, _| k[0, 7] == "BUNDLE_" }
      env.delete("BUNDLER_SETUP")

      if env.key?("RUBYOPT")
        rubyopt = env["RUBYOPT"].split(" ")
        rubyopt.delete("-r#{File.expand_path("bundler/setup", __dir__)}")
        rubyopt.delete("-rbundler/setup")
        env["RUBYOPT"] = rubyopt.join(" ")
      end

      if env.key?("RUBYLIB")
        rubylib = env["RUBYLIB"].split(File::PATH_SEPARATOR)
        rubylib.delete(__dir__)
        env["RUBYLIB"] = rubylib.join(File::PATH_SEPARATOR)
      end

      env
    end

    def load_marshal(data, marshal_proc: nil)
      Marshal.load(data, marshal_proc)
    rescue TypeError => e
      raise MarshalError, "#{e.class}: #{e.message}"
    end

    def eval_yaml_gemspec(path, contents)
      Kernel.require "psych"

      Gem::Specification.from_yaml(contents)
    rescue ::Psych::SyntaxError, ArgumentError, Gem::EndOfYAMLException, Gem::Exception
      eval_gemspec(path, contents)
    end

    def eval_gemspec(path, contents)
      eval(contents, TOPLEVEL_BINDING.dup, path.expand_path.to_s)
    rescue ScriptError, StandardError => e
      msg = "There was an error while loading `#{path.basename}`: #{e.message}"

      raise GemspecError, Dsl::DSLError.new(msg, path.to_s, e.backtrace, contents)
    end

    def configure_gem_path
      unless use_system_gems?
        # this needs to be empty string to cause
        # PathSupport.split_gem_path to only load up the
        # Bundler --path setting as the GEM_PATH.
        Bundler::SharedHelpers.set_env "GEM_PATH", ""
      end
    end

    def configure_gem_home(path)
      Bundler::SharedHelpers.set_env "GEM_HOME", path.to_s
    end

    def tmp_home_path
      Kernel.send(:require, "tmpdir")
      SharedHelpers.filesystem_access(Dir.tmpdir) do
        path = Bundler.tmp
        at_exit { Bundler.rm_rf(path) }
        path
      end
    end

    # @param env [Hash]
    def with_env(env)
      backup = ENV.to_hash
      ENV.replace(env)
      yield
    ensure
      ENV.replace(backup)
    end
  end
end
