# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cli/parser"

module Homebrew
  # This class provides a framework for implementing subcommands within a brew command.
  # It extends the AbstractCommand functionality by:
  #
  # 1. Providing a clean hierarchy of command/subcommand relationships
  # 2. Allowing subcommands to define their own specific arguments
  # 3. Supporting inheritance of parent command arguments where applicable
  # 4. Generating proper help text for both main commands and subcommands
  # 5. Facilitating improved tab completion by properly organizing command options
  #
  # @api public
  module AbstractSubcommandMod
    extend T::Helpers
    include Kernel

    module ClassWithSubcommands
      include Kernel

      sig { returns(T::Hash[String, T.class_of(AbstractSubcommand)]) }
      def subcommands
        @subcommands = T.let(@subcommands, T.nilable(T::Hash[String, T.class_of(AbstractSubcommand)]))
        @subcommands = {} if @subcommands.nil?
        @subcommands
      end

      sig { void }
      def register_all_subcommands
        Module.instance_method(:constants).bind_call(self).each do |const_name|
          const = Module.instance_method(:const_get).bind_call(self, const_name)
          register_subcommand(const) if const.is_a?(Class) && const < AbstractSubcommand
        end
      end

      sig { params(subcommand_class: T.class_of(AbstractSubcommand), aliases: T::Array[String]).void }
      def register_subcommand(subcommand_class, aliases = [])
        primary_name = subcommand_class.command_name
        subcommands[primary_name] = subcommand_class

        aliases.each do |alias_name|
          subcommands[alias_name] = subcommand_class
        end
      end
    end

    sig { returns(T::Hash[String, T.class_of(AbstractSubcommand)]) }
    def subcommands
      parent_class = T.cast(Object.instance_method(:class).bind_call(self),
                            T.all(T.class_of(AbstractCommand), ClassWithSubcommands))
      parent_class.subcommands
    end

    sig { params(base: Module).void }
    def self.included(base)
      base.extend(ClassMethods)
      base.extend(ClassWithSubcommands)

      base.singleton_class.prepend(Module.new do
        include Kernel

        sig { params(subclass: T.class_of(AbstractCommand)).void }
        def inherited(subclass)
          super

          Kernel.at_exit do
            T.cast(subclass, T.all(T.class_of(AbstractCommand), ClassWithSubcommands)).register_all_subcommands
          end
        end
      end)
    end

    module ClassMethods
      sig { params(block: T.proc.bind(CLI::Parser).void).void }
      def shared_args(&block)
        @shared_args_block = T.let(block, T.nilable(T.proc.void))
      end

      sig { returns(T.nilable(T.proc.void)) }
      def shared_args_block
        @shared_args_block
      end
    end
  end

  # Base class for all subcommands
  #
  # Subcommands implement their own argument parsing and help text generation
  # while inheriting shared arguments from their parent command.
  #
  # @api public
  class AbstractSubcommand < AbstractCommand
    extend T::Helpers
    include Kernel

    abstract!

    class << self
      include Kernel

      sig { returns(String) }
      def command_name
        require "utils"

        Utils.underscore(T.must(name).split("::").fetch(-1))
             .tr("_", "-")
      end

      sig { returns(T::Array[String]) }
      def command_names
        T.cast(parent_command_class, AbstractSubcommandMod::ClassWithSubcommands)
         .subcommands.select { |_, klass| klass == self }.keys
      end

      sig { returns(T.class_of(AbstractCommand)) }
      def parent_command_class
        name_parts = T.must(name).split("::")
        parts_without_last = T.must(name_parts[0..-2])
        parent_module = parts_without_last.join("::")
        Object.const_get(parent_module)
      end

      sig { returns(CLI::Parser) }
      def parser
        parent_class = T.cast(parent_command_class, AbstractSubcommandMod::ClassMethods)
        parser = CLI::Parser.new(self, &@parser_block)

        shared_block = parent_class.shared_args_block
        parser.instance_eval(&T.unsafe(shared_block)) if shared_block

        parser
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def common_args
      args_obj = T.unsafe(args)
      {
        global:  args_obj.respond_to?(:global?) ? args_obj.global? : false,
        file:    args_obj.respond_to?(:file) ? args_obj.file : nil,
        verbose: args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false,
      }
    end

    sig { abstract.void }
    def run; end
  end

  module SubcommandDispatcher
    extend T::Helpers

    abstract!

    sig { abstract.returns(T::Hash[String, T.class_of(AbstractSubcommand)]) }
    def subcommands; end

    sig { params(subcommand_name: T.nilable(String), args: T::Array[String]).returns(T::Boolean) }
    def dispatch_subcommand(subcommand_name, args = [])
      return false unless subcommand_name

      subcommand_class = subcommands[subcommand_name]
      return false unless subcommand_class

      subcommand_class.new(args).run
      true
    end

    sig { returns(String) }
    def available_subcommands_help
      cmd_list = subcommands.keys.uniq.sort
      return "" if cmd_list.empty?

      <<~EOS
        Available subcommands:
          #{cmd_list.join(", ")}
      EOS
    end
  end

  module TargetableCommand
    include Kernel

    sig { params(loaded: T::Boolean).returns(T::Array[T.untyped]) }
    def get_targets(loaded: true)
      local_args = T.let(
        if Kernel.instance_variable_defined?(:@args)
          Kernel.instance_variable_get(:@args)
        else
          (Kernel.respond_to?(:args) ? Kernel.send(:args) : nil)
        end,
        T.untyped,
      )

      if local_args.respond_to?(:all?) && local_args.all?
        Services::Formulae.available_services(
          loaded:    loaded,
          skip_root: !Services::System.root?,
        )
      elsif local_args.respond_to?(:named_args) && local_args.named_args.respond_to?(:present?) &&
            local_args.named_args.present?
        local_args.named_args.map do |f|
          Services::FormulaWrapper.new(Formulary.factory(T.cast(f, T.any(Pathname, String))))
        end
      else
        []

      end
    end
  end
end
