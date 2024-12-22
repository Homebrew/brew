# typed: strict
# frozen_string_literal: true

module Homebrew
  module CLI
    class Args
      # Represents a processed option. The array elements are:
      #   0: short option name (e.g. "-d")
      #   1: long option name (e.g. "--debug")
      #   2: option description (e.g. "Print debugging information")
      #   3: whether the option is hidden
      OptionsType = T.type_alias { T::Array[[String, T.nilable(String), String, T::Boolean]] }

      sig { returns(T::Array[String]) }
      attr_reader :options_only, :flags_only, :remaining

      sig { void }
      def initialize
        require "cli/named_args"

        @cli_args = T.let(nil, T.nilable(T::Array[String]))
        @processed_options = T.let([], OptionsType)
        @options_only = T.let([], T::Array[String])
        @flags_only = T.let([], T::Array[String])
        @cask_options = T.let(false, T::Boolean)
        @table = T.let({}, T::Hash[Symbol, T.untyped])

        # Can set these because they will be overwritten by freeze_named_args!
        # (whereas other values below will only be overwritten if passed).
        @named = T.let(NamedArgs.new(parent: self), T.nilable(NamedArgs))
        @remaining = T.let([], T::Array[String])
      end

      sig { params(remaining_args: T::Array[T.any(T::Array[String], String)]).void }
      def freeze_remaining_args!(remaining_args) = @remaining.replace(remaining_args).freeze

      sig { params(named_args: T::Array[String], cask_options: T::Boolean, without_api: T::Boolean).void }
      def freeze_named_args!(named_args, cask_options:, without_api:)
        @named = T.let(
          NamedArgs.new(
            *named_args.freeze,
            cask_options:,
            flags:         flags_only,
            force_bottle:  @table[:force_bottle?] || false,
            override_spec: @table[:HEAD?] ? :head : nil,
            parent:        self,
            without_api:,
          ),
          T.nilable(NamedArgs),
        )
      end

      sig { params(name: Symbol, value: T.untyped).void }
      def set_arg(name, value)
        @table[name] = value
      end

      sig { override.params(_blk: T.nilable(T.proc.params(x: T.untyped).void)).returns(T.untyped) }
      def tap(&_blk)
        return super if block_given? # Object#tap

        @table[:tap]
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
        T.must(@named)
      end

      sig { returns(T::Boolean) }
      def no_named? = named.empty?

      sig { returns(T::Array[String]) }
      def build_from_source_formulae
        if @table[:build_from_source?] || @table[:HEAD?] || @table[:build_bottle?]
          named.to_formulae.map(&:full_name)
        else
          []
        end
      end

      sig { returns(T::Array[String]) }
      def include_test_formulae
        if @table[:include_test?]
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
        if @table[:formula?] && !@table[:cask?]
          :formula
        elsif @table[:cask?] && !@table[:formula?]
          :cask
        end
      end

      sig { returns(T::Array[[Symbol, Symbol]]) }
      def os_arch_combinations
        skip_invalid_combinations = false

        oses = case (os_sym = @table[:os]&.to_sym)
        when nil
          [SimulateSystem.current_os]
        when :all
          skip_invalid_combinations = true

          OnSystem::ALL_OS_OPTIONS
        else
          [os_sym]
        end

        arches = case (arch_sym = @table[:arch]&.to_sym)
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
        @cli_args ||= @processed_options.filter_map do |short, long|
          option = long || short
          switch = :"#{option_to_name(option)}?"
          flag = option_to_name(option).to_sym
          if @table[switch] == true || @table[flag] == true
            option
          elsif @table[flag].instance_of? String
            "#{option}=#{@table[flag]}"
          elsif @table[flag].instance_of? Array
            "#{option}=#{@table[flag].join(",")}"
          end
        end.freeze
      end
    end
  end
end
