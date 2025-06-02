# frozen_string_literal: true

require_relative "plugin/api"

module Bundler
  module Plugin
    autoload :DSL,        File.expand_path("plugin/dsl", __dir__)
    autoload :Events,     File.expand_path("plugin/events", __dir__)
    autoload :Index,      File.expand_path("plugin/index", __dir__)
    autoload :Installer,  File.expand_path("plugin/installer", __dir__)
    autoload :SourceList, File.expand_path("plugin/source_list", __dir__)

    class MalformattedPlugin < PluginError; end
    class UndefinedCommandError < PluginError; end
    class UnknownSourceError < PluginError; end
    class PluginInstallError < PluginError; end

    PLUGIN_FILE_NAME = "plugins.rb".freeze

    module_function

    def reset!
      instance_variables.each {|i| remove_instance_variable(i) }

      @sources = {}
      @commands = {}
      @hooks_by_event = Hash.new {|h, k| h[k] = [] }
      @loaded_plugin_names = []
    end

    reset!

    # Installs a new plugin by the given name
    #
    # @param [Array<String>] names the name of plugin to be installed
    # @param [Hash] options various parameters as described in description.
    #               Refer to cli/plugin for available options
    def install(names, options)
      raise InvalidOption, "You cannot specify `--branch` and `--ref` at the same time." if options["branch"] && options["ref"]

      specs = Installer.new.install(names, options)

      save_plugins names, specs
    rescue PluginError
      specs_to_delete = specs.select {|k, _v| names.include?(k) && !index.commands.values.include?(k) }
      specs_to_delete.each_value {|spec| Bundler.rm_rf(spec.full_gem_path) }

      raise
    end

    # Uninstalls plugins by the given names
    #
    # @param [Array<String>] names the names of plugins to be uninstalled
    def uninstall(names, options)
      if names.empty? && !options[:all]
        Bundler.ui.error "No plugins to uninstall. Specify at least 1 plugin to uninstall.\n"\
          "Use --all option to uninstall all the installed plugins."
        return
      end

      names = index.installed_plugins if options[:all]
      if names.any?
        names.each do |name|
          if index.installed?(name)
            Bundler.rm_rf(index.plugin_path(name))
            index.unregister_plugin(name)
            Bundler.ui.info "Uninstalled plugin #{name}"
          else
            Bundler.ui.error "Plugin #{name} is not installed \n"
          end
        end
      else
        Bundler.ui.info "No plugins installed"
      end
    end

    # List installed plugins and commands
    #
    def list
      installed_plugins = index.installed_plugins
      if installed_plugins.any?
        output = String.new
        installed_plugins.each do |plugin|
          output << "#{plugin}\n"
          output << "-----\n"
          index.plugin_commands(plugin).each do |command|
            output << "  #{command}\n"
          end
          output << "\n"
        end
      else
        output = "No plugins installed"
      end
      Bundler.ui.info output
    end

    # Evaluates the Gemfile with a limited DSL and installs the plugins
    # specified by plugin method
    #
    # @param [Pathname] gemfile path
    # @param [Proc] block that can be evaluated for (inline) Gemfile
    def gemfile_install(gemfile = nil, &inline)
      Bundler.settings.temporary(:frozen => false, :deployment => false) do
        builder = DSL.new
        if block_given?
          builder.instance_eval(&inline)
        else
          builder.eval_gemfile(gemfile)
        end
        builder.check_primary_source_safety
        definition = builder.to_definition(nil, true)

        return if definition.dependencies.empty?

        plugins = definition.dependencies.map(&:name).reject {|p| index.installed? p }
        installed_specs = Installer.new.install_definition(definition)

        save_plugins plugins, installed_specs, builder.inferred_plugins
      end
    rescue RuntimeError => e
      unless e.is_a?(GemfileError)
        Bundler.ui.error "Failed to install plugin: #{e.message}\n  #{e.backtrace[0]}"
      end
      raise
    end

    # The index object used to store the details about the plugin
    def index
      @index ||= Index.new
    end

    # The directory root for all plugin related data
    #
    # If run in an app, points to local root, in app_config_path
    # Otherwise, points to global root, in Bundler.user_bundle_path("plugin")
    def root
      @root ||= if SharedHelpers.in_bundle?
        local_root
      else
        global_root
      end
    end

    def local_root
      Bundler.app_config_path.join("plugin")
    end

    # The global directory root for all plugin related data
    def global_root
      Bundler.user_bundle_path("plugin")
    end

    # The cache directory for plugin stuffs
    def cache
      @cache ||= root.join("cache")
    end

    # To be called via the API to register to handle a command
    def add_command(command, cls)
      @commands[command] = cls
    end

    # Checks if any plugin handles the command
    def command?(command)
      !index.command_plugin(command).nil?
    end

    # To be called from Cli class to pass the command and argument to
    # appropriate plugin class
    def exec_command(command, args)
      raise UndefinedCommandError, "Command `#{command}` not found" unless command? command

      load_plugin index.command_plugin(command) unless @commands.key? command

      @commands[command].new.exec(command, args)
    end

    # To be called via the API to register to handle a source plugin
    def add_source(source, cls)
      @sources[source] = cls
    end

    # Checks if any plugin declares the source
    def source?(name)
      !index.source_plugin(name.to_s).nil?
    end

    # @return [Class] that handles the source. The class includes API::Source
    def source(name)
      raise UnknownSourceError, "Source #{name} not found" unless source? name

      load_plugin(index.source_plugin(name)) unless @sources.key? name

      @sources[name]
    end

    # @param [Hash] The options that are present in the lock file
    # @return [API::Source] the instance of the class that handles the source
    #                       type passed in locked_opts
    def source_from_lock(locked_opts)
      src = source(locked_opts["type"])

      src.new(locked_opts.merge("uri" => locked_opts["remote"]))
    end

    # To be called via the API to register a hooks and corresponding block that
    # will be called to handle the hook
    def add_hook(event, &block)
      unless Events.defined_event?(event)
        raise ArgumentError, "Event '#{event}' not defined in Bundler::Plugin::Events"
      end
      @hooks_by_event[event.to_s] << block
    end

    # Runs all the hooks that are registered for the passed event
    #
    # It passes the passed arguments and block to the block registered with
    # the api.
    #
    # @param [String] event
    def hook(event, *args, &arg_blk)
      return unless Bundler.feature_flag.plugins?
      unless Events.defined_event?(event)
        raise ArgumentError, "Event '#{event}' not defined in Bundler::Plugin::Events"
      end

      plugins = index.hook_plugins(event)
      return unless plugins.any?

      (plugins - @loaded_plugin_names).each {|name| load_plugin(name) }

      @hooks_by_event[event].each {|blk| blk.call(*args, &arg_blk) }
    end

    # currently only intended for specs
    #
    # @return [String, nil] installed path
    def installed?(plugin)
      Index.new.installed?(plugin)
    end

    # Post installation processing and registering with index
    #
    # @param [Array<String>] plugins list to be installed
    # @param [Hash] specs of plugins mapped to installation path (currently they
    #               contain all the installed specs, including plugins)
    # @param [Array<String>] names of inferred source plugins that can be ignored
    def save_plugins(plugins, specs, optional_plugins = [])
      plugins.each do |name|
        next if index.installed?(name)

        spec = specs[name]

        save_plugin(name, spec, optional_plugins.include?(name))
      end
    end

    # Checks if the gem is good to be a plugin
    #
    # At present it only checks whether it contains plugins.rb file
    #
    # @param [Pathname] plugin_path the path plugin is installed at
    # @raise [MalformattedPlugin] if plugins.rb file is not found
    def validate_plugin!(plugin_path)
      plugin_file = plugin_path.join(PLUGIN_FILE_NAME)
      raise MalformattedPlugin, "#{PLUGIN_FILE_NAME} was not found in the plugin." unless plugin_file.file?
    end

    # Validates and registers a plugin.
    #
    # @param [String] name the name of the plugin
    # @param [Specification] spec of installed plugin
    # @param [Boolean] optional_plugin, removed if there is conflict with any
    #                     other plugin (used for default source plugins)
    #
    # @raise [PluginInstallError] if validation or registration raises any error
    def save_plugin(name, spec, optional_plugin = false)
      validate_plugin! Pathname.new(spec.full_gem_path)
      installed = register_plugin(name, spec, optional_plugin)
      Bundler.ui.info "Installed plugin #{name}" if installed
    rescue PluginError => e
      raise PluginInstallError, "Failed to install plugin `#{spec.name}`, due to #{e.class} (#{e.message})"
    end

    # Runs the plugins.rb file in an isolated namespace, records the plugin
    # actions it registers for and then passes the data to index to be stored.
    #
    # @param [String] name the name of the plugin
    # @param [Specification] spec of installed plugin
    # @param [Boolean] optional_plugin, removed if there is conflict with any
    #                     other plugin (used for default source plugins)
    #
    # @raise [MalformattedPlugin] if plugins.rb raises any error
    def register_plugin(name, spec, optional_plugin = false)
      commands = @commands
      sources = @sources
      hooks = @hooks_by_event

      @commands = {}
      @sources = {}
      @hooks_by_event = Hash.new {|h, k| h[k] = [] }

      load_paths = spec.load_paths
      Bundler.rubygems.add_to_load_path(load_paths)
      path = Pathname.new spec.full_gem_path

      begin
        load path.join(PLUGIN_FILE_NAME), true
      rescue StandardError => e
        raise MalformattedPlugin, "#{e.class}: #{e.message}"
      end

      if optional_plugin && @sources.keys.any? {|s| source? s }
        Bundler.rm_rf(path)
        false
      else
        index.register_plugin(name, path.to_s, load_paths, @commands.keys,
          @sources.keys, @hooks_by_event.keys)
        true
      end
    ensure
      @commands = commands
      @sources = sources
      @hooks_by_event = hooks
    end

    # Executes the plugins.rb file
    #
    # @param [String] name of the plugin
    def load_plugin(name)
      return unless name && !name.empty?

      # Need to ensure before this that plugin root where the rest of gems
      # are installed to be on load path to support plugin deps. Currently not
      # done to avoid conflicts
      path = index.plugin_path(name)

      Bundler.rubygems.add_to_load_path(index.load_paths(name))

      load path.join(PLUGIN_FILE_NAME)

      @loaded_plugin_names << name
    rescue RuntimeError => e
      Bundler.ui.error "Failed loading plugin #{name}: #{e.message}"
      raise
    end

    class << self
      private :load_plugin, :register_plugin, :save_plugins, :validate_plugin!
    end
  end
end
