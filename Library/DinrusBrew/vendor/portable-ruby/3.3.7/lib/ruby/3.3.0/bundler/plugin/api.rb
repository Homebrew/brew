# frozen_string_literal: true

module Bundler
  # This is the interfacing class represents the API that we intend to provide
  # the plugins to use.
  #
  # For plugins to be independent of the Bundler internals they shall limit their
  # interactions to methods of this class only. This will save them from breaking
  # when some internal change.
  #
  # Currently we are delegating the methods defined in Bundler class to
  # itself. So, this class acts as a buffer.
  #
  # If there is some change in the Bundler class that is incompatible to its
  # previous behavior or if otherwise desired, we can reimplement(or implement)
  # the method to preserve compatibility.
  #
  # To use this, either the class can inherit this class or use it directly.
  # For example of both types of use, refer the file `spec/plugins/command.rb`
  #
  # To use it without inheriting, you will have to create an object of this
  # to use the functions (except for declaration functions like command, source,
  # and hooks).
  module Plugin
    class API
      autoload :Source, File.expand_path("api/source", __dir__)

      # The plugins should declare that they handle a command through this helper.
      #
      # @param [String] command being handled by them
      # @param [Class] (optional) class that handles the command. If not
      #                 provided, the `self` class will be used.
      def self.command(command, cls = self)
        Plugin.add_command command, cls
      end

      # The plugins should declare that they provide a installation source
      # through this helper.
      #
      # @param [String] the source type they provide
      # @param [Class] (optional) class that handles the source. If not
      #                 provided, the `self` class will be used.
      def self.source(source, cls = self)
        cls.send :include, Bundler::Plugin::API::Source
        Plugin.add_source source, cls
      end

      def self.hook(event, &block)
        Plugin.add_hook(event, &block)
      end

      # The cache dir to be used by the plugins for storage
      #
      # @return [Pathname] path of the cache dir
      def cache_dir
        Plugin.cache.join("plugins")
      end

      # A tmp dir to be used by plugins
      # Accepts names that get concatenated as suffix
      #
      # @return [Pathname] object for the new directory created
      def tmp(*names)
        Bundler.tmp(["plugin", *names].join("-"))
      end

      def method_missing(name, *args, &blk)
        return Bundler.send(name, *args, &blk) if Bundler.respond_to?(name)

        return SharedHelpers.send(name, *args, &blk) if SharedHelpers.respond_to?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        SharedHelpers.respond_to?(name, include_private) ||
          Bundler.respond_to?(name, include_private) || super
      end
    end
  end
end
