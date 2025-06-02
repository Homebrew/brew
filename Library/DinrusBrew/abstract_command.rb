# typed: strong
# frozen_string_literal: true

require "cli/parser"
require "shell_command"

module DinrusBrew
  # Создайте подкласс для реализации команды `brew`. Предпочтительно объявить именованную
  # функцию в модуле `DinrusBrew`, так как:
  #
  # - Каждая Command обитает в изолированном пространстве имён.
  # - Каждая Command реализует определённый интерфейс.
  # - `args` доступны как методы экземпляра и не требуют передачи в качестве аргумента
  #    вспомогательным методам.
  # - Подклассам более не нужно ссылаться на `CLI::Parser` или явно разбирать аргументы.
  #
  # Для субклассирования нужно реализовать метод `run` и предоставить блок `cmd_args`
  # для документирования команды и допустимых аргументов к ней.
  # Чтобы сгенерировать сигнатуры методов для аргументов команды, выполните
  # `brew typecheck --update`.
  #
  # @api public
  class AbstractCommand
    extend T::Helpers

    abstract!

    class << self
      sig { returns(T.nilable(T.class_of(CLI::Args))) }
      attr_reader :args_class

      sig { returns(String) }
      def command_name
        require "utils"

        Utils.underscore(T.must(name).split("::").fetch(-1))
             .tr("_", "-")
             .delete_suffix("-cmd")
      end

      # @return the AbstractCommand subclass associated with the brew CLI command name.
      sig { params(name: String).returns(T.nilable(T.class_of(AbstractCommand))) }
      def command(name) = subclasses.find { _1.command_name == name }

      sig { returns(T::Boolean) }
      def dev_cmd? = T.must(name).start_with?("DinrusBrew::DevCmd")

      sig { returns(T::Boolean) }
      def ruby_cmd? = !include?(DinrusBrew::ShellCommand)

      sig { returns(CLI::Parser) }
      def parser = CLI::Parser.new(self, &@parser_block)

      private

      # The description and arguments of the command should be defined within this block.
      #
      # @api public
      sig { params(block: T.proc.bind(CLI::Parser).void).void }
      def cmd_args(&block)
        @parser_block = T.let(block, T.nilable(T.proc.void))
        @args_class = T.let(const_set(:Args, Class.new(CLI::Args)), T.nilable(T.class_of(CLI::Args)))
      end
    end

    sig { returns(CLI::Args) }
    attr_reader :args

    sig { params(argv: T::Array[String]).void }
    def initialize(argv = ARGV.freeze)
      @args = T.let(self.class.parser.parse(argv), CLI::Args)
    end

    # This method will be invoked when the command is run.
    #
    # @api public
    sig { abstract.void }
    def run; end
  end

  module Cmd
    # The command class for `brew` itself, allowing its args to be parsed.
    class Brew < AbstractCommand; end
  end
end
