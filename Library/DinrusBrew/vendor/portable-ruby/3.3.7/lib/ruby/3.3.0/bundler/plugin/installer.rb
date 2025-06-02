# frozen_string_literal: true

module Bundler
  # Handles the installation of plugin in appropriate directories.
  #
  # This class is supposed to be wrapper over the existing gem installation infra
  # but currently it itself handles everything as the Source's subclasses (e.g. Source::RubyGems)
  # are heavily dependent on the Gemfile.
  module Plugin
    class Installer
      autoload :Rubygems, File.expand_path("installer/rubygems", __dir__)
      autoload :Git,      File.expand_path("installer/git", __dir__)
      autoload :Path, File.expand_path("installer/path", __dir__)

      def install(names, options)
        check_sources_consistency!(options)

        version = options[:version] || [">= 0"]

        if options[:git]
          install_git(names, version, options)
        elsif options[:path]
          install_path(names, version, options[:path])
        else
          sources = options[:source] || Gem.sources
          install_rubygems(names, version, sources)
        end
      end

      # Installs the plugin from Definition object created by limited parsing of
      # Gemfile searching for plugins to be installed
      #
      # @param [Definition] definition object
      # @return [Hash] map of names to their specs they are installed with
      def install_definition(definition)
        def definition.lock(*); end
        definition.resolve_remotely!
        specs = definition.specs

        install_from_specs specs
      end

      private

      def check_sources_consistency!(options)
        if options.key?(:git) && options.key?(:local_git)
          raise InvalidOption, "Remote and local plugin git sources can't be both specified"
        end

        # back-compat; local_git is an alias for git
        if options.key?(:local_git)
          Bundler::SharedHelpers.major_deprecation(2, "--local_git is deprecated, use --git")
          options[:git] = options.delete(:local_git)
        end

        if (options.keys & [:source, :git, :path]).length > 1
          raise InvalidOption, "Only one of --source, --git, or --path may be specified"
        end

        if (options.key?(:branch) || options.key?(:ref)) && !options.key?(:git)
          raise InvalidOption, "--#{options.key?(:branch) ? "branch" : "ref"} can only be used with git sources"
        end

        if options.key?(:branch) && options.key?(:ref)
          raise InvalidOption, "--branch and --ref can't be both specified"
        end
      end

      def install_git(names, version, options)
        source_list = SourceList.new
        source = source_list.add_git_source({ "uri" => options[:git],
                                              "branch" => options[:branch],
                                              "ref" => options[:ref] })

        install_all_sources(names, version, source_list, source)
      end

      def install_path(names, version, path)
        source_list = SourceList.new
        source = source_list.add_path_source({ "path" => path, "root_path" => SharedHelpers.pwd })

        install_all_sources(names, version, source_list, source)
      end

      # Installs the plugin from rubygems source and returns the path where the
      # plugin was installed
      #
      # @param [String] name of the plugin gem to search in the source
      # @param [Array] version of the gem to install
      # @param [String, Array<String>] source(s) to resolve the gem
      #
      # @return [Hash] map of names to the specs of plugins installed
      def install_rubygems(names, version, sources)
        source_list = SourceList.new

        Array(sources).each {|remote| source_list.add_global_rubygems_remote(remote) }

        install_all_sources(names, version, source_list)
      end

      def install_all_sources(names, version, source_list, source = nil)
        deps = names.map {|name| Dependency.new(name, version, { "source" => source }) }

        Bundler.configure_gem_home_and_path(Plugin.root)

        Bundler.settings.temporary(deployment: false, frozen: false) do
          definition = Definition.new(nil, deps, source_list, true)

          install_definition(definition)
        end
      end

      # Installs the plugins and deps from the provided specs and returns map of
      # gems to their paths
      #
      # @param specs to install
      #
      # @return [Hash] map of names to the specs
      def install_from_specs(specs)
        paths = {}

        specs.each do |spec|
          spec.source.install spec

          paths[spec.name] = spec
        end

        paths
      end
    end
  end
end
