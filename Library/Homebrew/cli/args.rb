# typed: strict
# frozen_string_literal: true

require "ostruct"

module Homebrew
  module CLI
    class Args < OpenStruct
      # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
      # rubocop:disable Style/MutableConstant
      # Represents a processed option. The array elements are:
      #   0: short option name (e.g. "-d")
      #   1: long option name (e.g. "--debug")
      #   2: option description (e.g. "Print debugging information")
      #   3: whether the option is hidden
      OptionsType = T.type_alias { T::Array[[String, T.nilable(String), String, T::Boolean]] }
      # rubocop:enable Style/MutableConstant

      sig { returns(T::Array[String]) }
      attr_reader :options_only, :flags_only

      # undefine tap to allow --tap argument
      undef tap

      sig { void }
      def initialize
        require "cli/named_args"

        super

        @cli_args = T.let(nil, T.nilable(T::Array[String]))
        @processed_options = T.let([], OptionsType)
        @options_only = T.let([], T::Array[String])
        @flags_only = T.let([], T::Array[String])
        @cask_options = T.let(false, T::Boolean)
        @table = T.let({}, T::Hash[Symbol, T.untyped])

        # Can set these because they will be overwritten by freeze_named_args!
        # (whereas other values below will only be overwritten if passed).
        self[:named] = NamedArgs.new(parent: self)
        self[:remaining] = []
      end

      sig { params(remaining_args: T::Array[T.any(T::Array[String], String)]).void }
      def freeze_remaining_args!(remaining_args)
        self[:remaining] = remaining_args.freeze
      end

      sig { params(named_args: T::Array[String], cask_options: T::Boolean, without_api: T::Boolean).void }
      def freeze_named_args!(named_args, cask_options:, without_api:)
        options = {}
        options[:force_bottle] = true if self[:force_bottle?]
        options[:override_spec] = :head if self[:HEAD?]
        options[:flags] = flags_only unless flags_only.empty?
        self[:named] = NamedArgs.new(
          *named_args.freeze,
          parent:       self,
          cask_options:,
          without_api:,
          **options,
        )
      end

      sig { params(processed_options: OptionsType).void }
      def freeze_processed_options!(processed_options)
        # Reset cache values reliant on processed_options
        @cli_args = nil

        @processed_options += processed_options
        @processed_options.freeze

        @options_only = cli_args.select { _1.start_with?("-") }.freeze
        @flags_only = cli_args.select { _1.start_with?("--") }.freeze
      end

      sig { returns(NamedArgs) }
      def named
        require "formula"
        self[:named]
      end

      sig { returns(T::Boolean) }
      def no_named? = named.blank?

      sig { returns(T::Array[String]) }
      def build_from_source_formulae
        if build_from_source? || self[:HEAD?] || self[:build_bottle?]
          named.to_formulae.map(&:full_name)
        else
          []
        end
      end

      sig { returns(T::Array[String]) }
      def include_test_formulae
        if include_test?
          named.to_formulae.map(&:full_name)
        else
          []
        end
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def value(name)
        arg_prefix = "--#{name}="
        flag_with_value = flags_only.find { |arg| arg.start_with?(arg_prefix) }
        return unless flag_with_value

        flag_with_value.delete_prefix(arg_prefix)
      end

      sig { returns(Context::ContextStruct) }
      def context
        Context::ContextStruct.new(debug: debug?, quiet: quiet?, verbose: verbose?)
      end

      sig { returns(T.nilable(Symbol)) }
      def only_formula_or_cask
        if formula? && !cask?
          :formula
        elsif cask? && !formula?
          :cask
        end
      end

      sig { returns(T::Array[[Symbol, Symbol]]) }
      def os_arch_combinations
        skip_invalid_combinations = false

        oses = case (os_sym = os&.to_sym)
        when nil
          [SimulateSystem.current_os]
        when :all
          skip_invalid_combinations = true

          OnSystem::ALL_OS_OPTIONS
        else
          [os_sym]
        end

        arches = case (arch_sym = arch&.to_sym)
        when nil
          [SimulateSystem.current_arch]
        when :all
          skip_invalid_combinations = true
          OnSystem::ARCH_OPTIONS
        else
          [arch_sym]
        end

        oses.product(arches).select do |os, arch|
          if skip_invalid_combinations
            bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
            bottle_tag.valid_combination?
          else
            true
          end
        end
      end

      private

      sig { params(option: String).returns(String) }
      def option_to_name(option)
        option.sub(/\A--?/, "")
              .tr("-", "_")
      end

      sig { returns(T::Array[String]) }
      def cli_args
        return @cli_args if @cli_args

        @cli_args = []
        @processed_options.each do |short, long|
          option = long || short
          switch = :"#{option_to_name(option)}?"
          flag = option_to_name(option).to_sym
          if @table[switch] == true || @table[flag] == true
            @cli_args << option
          elsif @table[flag].instance_of? String
            @cli_args << "#{option}=#{@table[flag]}"
          elsif @table[flag].instance_of? Array
            @cli_args << "#{option}=#{@table[flag].join(",")}"
          end
        end
        @cli_args.freeze
      end

      sig { params(method_name: Symbol, _include_private: T::Boolean).returns(T::Boolean) }
      def respond_to_missing?(method_name, _include_private = false)
        @table.key?(method_name)
      end

      sig { params(method_name: Symbol, args: T.untyped).returns(T.untyped) }
      def method_missing(method_name, *args)
        return_value = super

        # Once we are frozen, verify any arg method calls are already defined in the table.
        # The default OpenStruct behaviour is to return nil for anything unknown.
        if frozen? && args.empty? && !@table.key?(method_name)
          raise NoMethodError, "CLI arg for `#{method_name}` is not declared for this command"
        end

        return_value
      end
    end
  end
end
