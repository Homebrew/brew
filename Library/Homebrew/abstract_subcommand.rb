# typed: strict
# frozen_string_literal: true

require "cli/parser"
require "abstract_command"
require "utils/output"

module Homebrew
  # Subclass this to implement a subcommand for a `brew` command.
  #
  # @api public
  class AbstractSubcommand
    extend T::Helpers
    include Utils::Output::Mixin

    abstract!

    class << self
      sig { returns(String) }
      def subcommand_name
        require "utils"

        class_name = name
        raise TypeError, "anonymous subcommands do not have names" if class_name.nil?

        Utils.underscore(class_name.split("::").fetch(-1))
             .tr("_", "-")
             .delete_suffix("-subcommand")
      end

      sig { params(command: T.class_of(Homebrew::AbstractCommand)).returns(T::Array[T.class_of(AbstractSubcommand)]) }
      def subcommands_for(command)
        namespace = "#{command.name}::"
        # Qualified so this behaves the same whether called on `AbstractSubcommand`
        # itself or (as `command` does below) on one of its subclasses.
        Homebrew::AbstractSubcommand.subclasses.select do |subcommand|
          subcommand.name&.start_with?(namespace)
        end
      end

      sig { returns(T.class_of(Homebrew::AbstractCommand)) }
      def command
        found = Homebrew::AbstractCommand.subclasses.find { |candidate| subcommands_for(candidate).include?(self) }
        raise TypeError, "#{self} is not nested under a `Homebrew::AbstractCommand`" if found.nil?

        found
      end

      # A module `extend`ed onto this subcommand's `args` in `#initialize`, so `is_a?`
      # genuinely holds for the type named in the generated RBI (see
      # `Tapioca::Compilers::SubcommandArgs`) instead of only approximating it statically.
      sig { returns(T::Module[T.anything]) }
      def args_module
        @args_module ||= T.let(const_set(:Args, Module.new), T.nilable(T::Module[T.anything]))
      end

      sig { params(parser: CLI::Parser, command: T.class_of(Homebrew::AbstractCommand)).void }
      def define_all(parser, command:)
        subcommands_for(command).each do |subcommand|
          subcommand.define(parser)
          subcommand.args_module
        end
      end

      sig { params(parser: CLI::Parser).void }
      def define(parser)
        parser_block = @parser_block
        raise TypeError, "subcommand arguments have not been defined" if parser_block.nil?

        parser.subcommand(
          subcommand_name,
          aliases:       @aliases || [],
          alias_options: @alias_options || {},
          default:       @default || false,
        ) do
          instance_eval(&parser_block)
        end
      end

      private

      # The description and arguments of the subcommand should be defined within this block.
      #
      # @api public
      sig {
        params(
          aliases:       T::Array[String],
          alias_options: T::Hash[String, String],
          default:       T::Boolean,
          block:         T.proc.bind(CLI::Parser).void,
        ).void
      }
      def subcommand_args(aliases: [], alias_options: {}, default: false, &block)
        @aliases = T.let(aliases, T.nilable(T::Array[String]))
        @alias_options = T.let(alias_options, T.nilable(T::Hash[String, String]))
        @default = T.let(default, T.nilable(T::Boolean))
        @parser_block = T.let(block, T.nilable(T.proc.void))
      end
    end

    sig { returns(CLI::Args) }
    attr_reader :args

    sig {
      params(args: CLI::Args, context: T.anything, targets: T.anything, quiet: T::Boolean,
             cleanup: T::Boolean).void
    }
    def initialize(args, context: nil, targets: nil, quiet: false, cleanup: true)
      # `args` is frozen by `CLI::Parser#parse`, so `extend` needs an unfrozen clone
      # (which, unlike `dup`, keeps the singleton methods the parser defined on it).
      @args = T.let(args.clone(freeze: false).extend(self.class.args_module).freeze, CLI::Args)
      @context = context
      @targets = targets
      @quiet = quiet
      @cleanup = cleanup
    end

    # Only commands with subcommands that use `context` (currently `Bundle`) narrow this.
    sig { returns(T.anything) }
    attr_reader :context

    # Only commands with subcommands that use `targets` (currently `Services`) narrow this.
    sig { returns(T.anything) }
    attr_reader :targets

    sig { returns(T::Boolean) }
    attr_reader :quiet

    sig { returns(T::Boolean) }
    attr_reader :cleanup

    # This method will be invoked when the subcommand is run.
    #
    # @api public
    sig { abstract.void }
    def run; end
  end
end
