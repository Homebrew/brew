# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "abstract_subcommand"
require_relative "args"

module Tapioca
  module Compilers
    class SubcommandArgs < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(Homebrew::AbstractSubcommand) } }

      sig { override.returns(T::Enumerable[T.class_of(Homebrew::AbstractSubcommand)]) }
      def self.gather_constants
        # require all the commands to ensure the subcommand subclasses are defined
        ["cmd", "dev-cmd"].each do |dir|
          Dir[File.join(__dir__, "../../../#{dir}", "*.rb")].each { require(it) }
        end
        Homebrew::AbstractSubcommand.subclasses
      end

      sig { override.void }
      def decorate
        command = constant.command
        command_args_class_name = command.args_class&.name
        raise "#{command} has no `Args` class; does it call `cmd_args`?" if command_args_class_name.nil?

        # The command's own methods are also defined on this shared `Args` instance,
        # so they must be filtered out here rather than read via `.methods(false)`.
        parser = command.parser
        method_names = Args.subcommand_method_names(parser, constant.subcommand_name)

        args_module = constant.args_module
        args_module_name = args_module.name
        raise "#{args_module} has no name" if args_module_name.nil?

        root.create_path(args_module) do |klass|
          Args.create_args_methods(klass, parser, method_names)
        end
        root.create_path(constant) do |klass|
          klass.create_method("args", return_type: "T.all(#{command_args_class_name}, #{args_module_name})")
        end
      end
    end
  end
end
