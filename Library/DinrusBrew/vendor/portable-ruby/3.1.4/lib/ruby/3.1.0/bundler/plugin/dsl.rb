# frozen_string_literal: true

module Bundler
  module Plugin
    # Dsl to parse the Gemfile looking for plugins to install
    class DSL < Bundler::Dsl
      class PluginGemfileError < PluginError; end
      alias_method :_gem, :gem # To use for plugin installation as gem

      # So that we don't have to override all there methods to dummy ones
      # explicitly.
      # They will be handled by method_missing
      [:gemspec, :gem, :install_if, :platforms, :env].each {|m| undef_method m }

      # This lists the plugins that was added automatically and not specified by
      # the user.
      #
      # When we encounter :type attribute with a source block, we add a plugin
      # by name bundler-source-<type> to list of plugins to be installed.
      #
      # These plugins are optional and are not installed when there is conflict
      # with any other plugin.
      attr_reader :inferred_plugins

      def initialize
        super
        @sources = Plugin::SourceList.new
        @inferred_plugins = [] # The source plugins inferred from :type
      end

      def plugin(name, *args)
        _gem(name, *args)
      end

      def method_missing(name, *args)
        raise PluginGemfileError, "Undefined local variable or method `#{name}' for Gemfile" unless Bundler::Dsl.method_defined? name
      end

      def source(source, *args, &blk)
        options = args.last.is_a?(Hash) ? args.pop.dup : {}
        options = normalize_hash(options)
        return super unless options.key?("type")

        plugin_name = "bundler-source-#{options["type"]}"

        return if @dependencies.any? {|d| d.name == plugin_name }

        plugin(plugin_name)
        @inferred_plugins << plugin_name
      end
    end
  end
end
