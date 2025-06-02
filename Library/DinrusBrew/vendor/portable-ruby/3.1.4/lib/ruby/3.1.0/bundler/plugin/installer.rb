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

      def install(names, options)
        check_sources_consistency!(options)

        version = options[:version] || [">= 0"]

        if options[:git]
          install_git(names, version, options)
        elsif options[:local_git]
          install_local_git(names, version, options)
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
      end

      def install_git(names, version, options)
        uri = options.delete(:git)
        options["uri"] = uri

        install_all_sources(names, version, options, options[:source])
      end

      def install_local_git(names, version, options)
        uri = options.delete(:local_git)
        options["uri"] = uri

        install_all_sources(names, version, options, options[:source])
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
        install_all_sources(names, version, nil, sources)
      end

      def install_all_sources(names, version, git_source_options, rubygems_source)
        source_list = SourceList.new

        source_list.add_git_source(git_source_options) if git_source_options
        Array(rubygems_source).each {|remote| source_list.add_global_rubygems_remote(remote) } if rubygems_source

        deps = names.map {|name| Dependency.new name, version }

        Bundler.configure_gem_home_and_path(Plugin.root)

        definition = Definition.new(nil, deps, source_list, true)
        install_definition(definition)
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
