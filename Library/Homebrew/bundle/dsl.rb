# typed: strict
# frozen_string_literal: true

require "bundle/package_type"
require "utils"

module Homebrew
  module Bundle
    class Dsl
      class Entry
        sig { returns(Symbol) }
        attr_reader :type

        sig { returns(String) }
        attr_reader :name

        sig { returns(Homebrew::Bundle::EntryOptions) }
        attr_reader :options

        sig { params(type: Symbol, name: String, options: Homebrew::Bundle::EntryOptions).void }
        def initialize(type, name, options = {})
          @type = type
          @name = name
          @options = options
        end

        sig { returns(String) }
        def to_s
          name
        end
      end

      sig { returns(T::Array[Entry]) }
      attr_reader :entries

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :cask_arguments

      sig { returns(String) }
      attr_reader :input

      sig { params(path: T.any(Pathname, StringIO)).void }
      def initialize(path)
        @path = path
        path_read = path.read
        raise "path_read is nil" unless path_read

        @input = T.let(path_read, String)
        @entries = T.let([], T::Array[Entry])
        @cask_arguments = T.let({}, T::Hash[Symbol, T.untyped])

        begin
          process
        # Want to catch all exceptions for e.g. syntax errors.
        rescue Exception => e # rubocop:disable Lint/RescueException
          error_msg = "Invalid Brewfile: #{e.message}"
          raise RuntimeError, error_msg, e.backtrace
        end
      end

      sig { void }
      def process
        instance_eval(@input, @path.to_s)
      end

      sig { params(args: T::Hash[Symbol, T.untyped]).void }
      def cask_args(args)
        @cask_arguments.merge!(args)
      end

      sig { params(name: String, options: Homebrew::Bundle::EntryOptions).void }
      def brew(name, options = {})
        name = Homebrew::Bundle::Dsl.sanitize_brew_name(name)
        @entries << Entry.new(:brew, name, options)
      end

      sig { params(name: String, options: Homebrew::Bundle::EntryOptions).void }
      def cask(name, options = {})
        options[:full_name] = name
        name = Homebrew::Bundle::Dsl.sanitize_cask_name(name)
        options[:args] =
          @cask_arguments.merge T.cast(options.fetch(:args, {}), T::Hash[Symbol, NestedEntryOptionValue])
        @entries << Entry.new(:cask, name, options)
      end

      sig { params(name: String, clone_target: T.nilable(String), options: Homebrew::Bundle::EntryOptions).void }
      def tap(name, clone_target = nil, options = {})
        options[:clone_target] = clone_target
        name = Homebrew::Bundle::Dsl.sanitize_tap_name(name)
        @entries << Entry.new(:tap, name, options)
      end

      HOMEBREW_TAP_ARGS_REGEX = %r{^([\w-]+)/(homebrew-)?([\w-]+)$}
      HOMEBREW_CORE_FORMULA_REGEX = %r{^homebrew/homebrew/([\w+-.@]+)$}i
      HOMEBREW_TAP_FORMULA_REGEX = %r{^([\w-]+)/([\w-]+)/([\w+-.@]+)$}

      sig { params(name: String).returns(String) }
      def self.sanitize_brew_name(name)
        name = name.downcase
        if name =~ HOMEBREW_CORE_FORMULA_REGEX
          sanitized_name = Regexp.last_match(1)
          raise "sanitized_name is nil" unless sanitized_name

          sanitized_name
        elsif name =~ HOMEBREW_TAP_FORMULA_REGEX
          user = Regexp.last_match(1)
          repo = Regexp.last_match(2)
          name = Regexp.last_match(3)
          raise "repo is nil" unless repo

          "#{user}/#{repo.sub("homebrew-", "")}/#{name}"
        else
          name
        end
      end

      sig { params(name: String).returns(String) }
      def self.sanitize_tap_name(name)
        name = name.downcase
        if name =~ HOMEBREW_TAP_ARGS_REGEX
          "#{Regexp.last_match(1)}/#{Regexp.last_match(3)}"
        else
          name
        end
      end

      sig { params(name: String).returns(String) }
      def self.sanitize_cask_name(name)
        Utils.name_from_full_name(name).downcase
      end

      sig {
        override.params(method_name: Symbol, args: T.untyped, options: T.untyped,
                        block: T.nilable(T.proc.void)).returns(T.untyped)
      }
      def method_missing(method_name, *args, **options, &block)
        extension = Homebrew::Bundle.extension(method_name)
        return super if extension.nil?
        raise ArgumentError, "blocks are not supported for #{method_name}" if block

        # Extension DSL entries follow the existing Brewfile calling convention:
        # a required name plus an optional options hash, passed positionally,
        # with keywords, or both.
        unless (1..2).cover?(args.length)
          raise ArgumentError,
                "wrong number of arguments (given #{args.length}, expected 1..2)"
        end

        positional_options = {}
        if args.length == 2
          positional_options = args[1]
          unless positional_options.is_a? Hash
            raise ArgumentError,
                  "options(#{positional_options.inspect}) should be a Hash object"
          end
        end

        @entries << extension.entry(args.first, positional_options.merge(options))
      end

      sig { override.params(method_name: T.any(String, Symbol), include_private: T::Boolean).returns(T::Boolean) }
      def respond_to_missing?(method_name, include_private = false)
        Homebrew::Bundle.extension(method_name).present? || super
      end
    end
  end
end

# Load extensions after `Dsl` is defined because their `entry` methods build
# `Dsl::Entry` instances.
require "bundle/extensions"
