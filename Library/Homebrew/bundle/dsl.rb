# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    class Dsl
      class Entry
        attr_reader :type, :name, :options

        def initialize(type, name, options = {})
          @type = type
          @name = name
          @options = options
        end

        def to_s
          name
        end
      end

      attr_reader :entries, :cask_arguments, :input

      def initialize(path)
        @path = path
        @input = path.read
        @entries = []
        @cask_arguments = {}

        begin
          process
        # Want to catch all exceptions for e.g. syntax errors.
        rescue Exception => e # rubocop:disable Lint/RescueException
          error_msg = "Invalid Brewfile: #{e.message}"
          raise RuntimeError, error_msg, e.backtrace
        end
      end

      def process
        instance_eval(@input, @path.to_s)
      end

      def cask_args(args)
        raise "cask_args(#{args.inspect}) should be a Hash object" unless args.is_a? Hash

        @cask_arguments = args
      end

      def brew(name, options = {})
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
        raise "options(#{options.inspect}) should be a Hash object" unless options.is_a? Hash

        name = Homebrew::Bundle::Dsl.sanitize_brew_name(name)
        @entries << Entry.new(:brew, name, options)
      end

      def cask(name, options = {})
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
        raise "options(#{options.inspect}) should be a Hash object" unless options.is_a? Hash

        options[:full_name] = name
        name = Homebrew::Bundle::Dsl.sanitize_cask_name(name)
        options[:args] = @cask_arguments.merge options.fetch(:args, {})
        @entries << Entry.new(:cask, name, options)
      end

      def mas(name, options = {})
        id = options[:id]
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
        raise "options[:id](#{id}) should be an Integer object" unless id.is_a? Integer

        @entries << Entry.new(:mas, name, id:)
      end

      def whalebrew(name)
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String

        @entries << Entry.new(:whalebrew, name)
      end

      def vscode(name)
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String

        @entries << Entry.new(:vscode, name)
      end

      def tap(name, clone_target = nil, options = {})
        raise "name(#{name.inspect}) should be a String object" unless name.is_a? String
        if clone_target && !clone_target.is_a?(String)
          raise "clone_target(#{clone_target.inspect}) should be nil or a String object"
        end

        options[:clone_target] = clone_target
        name = Homebrew::Bundle::Dsl.sanitize_tap_name(name)
        @entries << Entry.new(:tap, name, options)
      end

      HOMEBREW_TAP_ARGS_REGEX = %r{^([\w-]+)/(homebrew-)?([\w-]+)$}
      HOMEBREW_CORE_FORMULA_REGEX = %r{^homebrew/homebrew/([\w+-.@]+)$}i
      HOMEBREW_TAP_FORMULA_REGEX = %r{^([\w-]+)/([\w-]+)/([\w+-.@]+)$}

      def self.sanitize_brew_name(name)
        name = name.downcase
        if name =~ HOMEBREW_CORE_FORMULA_REGEX
          Regexp.last_match(1)
        elsif name =~ HOMEBREW_TAP_FORMULA_REGEX
          user = Regexp.last_match(1)
          repo = T.must(Regexp.last_match(2))
          name = Regexp.last_match(3)
          "#{user}/#{repo.sub("homebrew-", "")}/#{name}"
        else
          name
        end
      end

      def self.sanitize_tap_name(name)
        name = name.downcase
        if name =~ HOMEBREW_TAP_ARGS_REGEX
          "#{Regexp.last_match(1)}/#{Regexp.last_match(3)}"
        else
          name
        end
      end

      def self.sanitize_cask_name(name)
        name = name.split("/").last if name.include?("/")
        name.downcase
      end

      def self.pluralize_dependency(installed_count)
        (installed_count == 1) ? "dependency" : "dependencies"
      end
    end
  end
end
