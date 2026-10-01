# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "cli/parser"

module Tapioca
  module Compilers
    class Args < Tapioca::Dsl::Compiler
      GLOBAL_OPTIONS = T.let(
        Homebrew::CLI::Parser.global_options.map do |short_option, long_option, _|
          [short_option, long_option].map { "#{Homebrew::CLI::Parser.option_to_name(it)}?" }
        end.flatten.freeze, T::Array[String]
      )

      ConstantType = type_member { { fixed: T.class_of(Homebrew::AbstractCommand) } }
      sig { override.returns(T::Enumerable[T.class_of(Homebrew::AbstractCommand)]) }
      def self.gather_constants
        # require all the commands to ensure the command subclasses are defined
        ["cmd", "dev-cmd"].each do |dir|
          Dir[File.join(__dir__, "../../../#{dir}", "*.rb")].each { require(it) }
        end
        Homebrew::AbstractCommand.subclasses
      end

      sig { override.void }
      def decorate
        cmd = constant
        # This is a dummy class to make the `brew` command parsable
        return if cmd == Homebrew::Cmd::Brew

        args_class_name = cmd.args_class&.name
        raise "#{cmd} has no `Args` class; does it call `cmd_args`?" if args_class_name.nil?

        parser = cmd.parser
        # Options declared inside a `subcommand` block are defined on the shared `Args`
        # instance too, but they belong on that subcommand's own class (see `SubcommandArgs`).
        method_names = parser.args.methods(false).select do |method_name|
          self.class.subcommands_for_method(parser, method_name).empty?
        end

        # `CLI::Parser` adds `subcommand` dynamically during parsing for commands
        # that define subcommands.
        method_names << :subcommand if parser.subcommands.present? && !method_names.include?(:subcommand)

        root.create_class(args_class_name, superclass_name: "Homebrew::CLI::Args") do |klass|
          self.class.create_args_methods(klass, parser, method_names)
        end
        root.create_path(constant) do |klass|
          klass.create_method("args", return_type: args_class_name)
        end
      end

      sig { params(parser: Homebrew::CLI::Parser, subcommand_name: String).returns(T::Array[Symbol]) }
      def self.subcommand_method_names(parser, subcommand_name)
        parser.args.methods(false).select do |method_name|
          subcommands_for_method(parser, method_name).include?(subcommand_name)
        end
      end

      sig { params(parser: Homebrew::CLI::Parser, method_name: Symbol).returns(T::Array[String]) }
      def self.subcommands_for_method(parser, method_name)
        parser.subcommands_for_option(method_name.to_s.delete_suffix("?"))
      end

      sig { params(parser: Homebrew::CLI::Parser).returns(T::Array[Symbol]) }
      def self.comma_arrays(parser)
        parser.instance_variable_get(:@non_global_processed_options)
              .filter_map { |k, v| parser.option_to_name(k).to_sym if v == :comma_array }
      end

      # A `--[no-]foo` switch has a genuine "unset" state distinct from `false` (see
      # `CLI::Parser#disable_switch`), so its accessor can return `nil` unless an `env:`
      # always resolves it to a real boolean first. The declared `--[no-]` form survives
      # verbatim in `option.long`, and `@switch_sources` already records that resolution,
      # so this needs no new parser state.
      sig { params(parser: Homebrew::CLI::Parser).returns(T::Array[Symbol]) }
      def self.negatable_switches(parser)
        switch_sources = parser.instance_variable_get(:@switch_sources)

        parser.processed_options.filter_map do |_short, long, _desc, _hidden|
          next unless long&.start_with?("--[no-]")

          name = parser.option_to_name(long)
          :"#{name}?" unless switch_sources.key?(name)
        end
      end

      sig {
        params(method_name: Symbol, comma_array_methods: T::Array[Symbol],
               negatable_methods: T::Array[Symbol]).returns(String)
      }
      def self.get_return_type(method_name, comma_array_methods, negatable_methods)
        if comma_array_methods.include?(method_name)
          "T.nilable(T::Array[String])"
        elsif negatable_methods.include?(method_name)
          "T.nilable(T::Boolean)"
        elsif method_name.end_with?("?")
          "T::Boolean"
        else
          "T.nilable(String)"
        end
      end

      sig { params(klass: RBI::Scope, parser: Homebrew::CLI::Parser, method_names: T::Array[Symbol]).void }
      def self.create_args_methods(klass, parser, method_names)
        comma_array_methods = comma_arrays(parser)
        negatable_methods = negatable_switches(parser)

        method_names.each do |method_name|
          method_name_str = method_name.to_s
          next if GLOBAL_OPTIONS.include?(method_name_str)

          return_type = get_return_type(method_name, comma_array_methods, negatable_methods)
          klass.create_method(method_name_str, return_type:)
        end
      end
    end
  end
end
