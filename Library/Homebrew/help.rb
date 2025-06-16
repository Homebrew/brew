# typed: strict
# frozen_string_literal: true

require "cli/parser"
require "commands"

module Homebrew
  # Helper module for printing help output.
  module Help
    sig {
      params(
        cmd:            T.nilable(String),
        empty_argv:     T::Boolean,
        usage_error:    T.nilable(String),
        remaining_args: T::Array[String],
      ).void
    }
    def self.help(cmd = nil, empty_argv: false, usage_error: nil, remaining_args: [])
      if cmd.nil?
        # Handle `brew` (no arguments).
        if empty_argv
          $stderr.puts HOMEBREW_HELP_MESSAGE
          exit 1
        end

        # Handle `brew (-h|--help|--usage|-?|help)` (no other arguments).
        puts HOMEBREW_HELP_MESSAGE
        exit 0
      end

      # Resolve command aliases and find file containing the implementation.
      path = Commands.path(cmd)

      # Display command-specific (or generic) help in response to `UsageError`.
      if usage_error
        $stderr.puts path ? command_help(cmd, path, remaining_args:) : HOMEBREW_HELP_MESSAGE
        $stderr.puts
        onoe usage_error
        exit 1
      end

      # Resume execution in `brew.rb` for unknown commands.
      return if path.nil?

      # Display help for internal command (or generic help if undocumented).
      puts command_help(cmd, path, remaining_args:)
      exit 0
    end

    sig {
      params(
        cmd:            String,
        path:           Pathname,
        remaining_args: T::Array[String],
      ).returns(String)
    }
    def self.command_help(cmd, path, remaining_args:)
      # Only some types of commands can have a parser.
      output = if Commands.valid_internal_cmd?(cmd) ||
                  Commands.valid_internal_dev_cmd?(cmd) ||
                  Commands.external_ruby_v2_cmd_path(cmd)
        parser_help(path, remaining_args:)
      end

      output ||= comment_help(path)

      output ||= if output.blank?
        opoo "No help text in: #{path}" if Homebrew::EnvConfig.developer?
        HOMEBREW_HELP_MESSAGE
      end

      output
    end
    private_class_method :command_help

    sig {
      params(
        path:           Pathname,
        remaining_args: T::Array[String],
      ).returns(T.nilable(String))
    }
    def self.parser_help(path, remaining_args:)
      # Let OptionParser generate help text for commands which have a parser.
      cmd_parser = CLI::Parser.from_cmd_path(path)
      return unless cmd_parser

      # Try parsing arguments here in order to show formula options in help output.
      cmd_parser.parse(remaining_args, ignore_invalid_options: true)
      cmd_parser.generate_help_text
    end
    private_class_method :parser_help

    sig { params(path: Pathname).returns(T::Array[String]) }
    def self.command_help_lines(path)
      path.read
          .lines
          .grep(/^#:/)
          .filter_map { |line| line.slice(2..-1)&.delete_prefix("  ") }
    end
    private_class_method :command_help_lines

    sig { params(path: Pathname).returns(T.nilable(String)) }
    def self.comment_help(path)
      # Otherwise read #: lines from the file.
      help_lines = command_help_lines(path)
      return if help_lines.blank?

      Formatter.format_help_text(help_lines.join, width: Formatter::COMMAND_DESC_WIDTH)
               .sub("@hide_from_man_page ", "")
               .sub(/^\* /, "#{Tty.bold}Usage: brew#{Tty.reset} ")
               .gsub(/`(.*?)`/m, "#{Tty.bold}\\1#{Tty.reset}")
               .gsub(%r{<([^\s]+?://[^\s]+?)>}) { |url| Formatter.url(url) }
               .gsub(/<(.*?)>/m, "#{Tty.underline}\\1#{Tty.reset}")
               .gsub(/\*(.*?)\*/m, "#{Tty.underline}\\1#{Tty.reset}")
    end
    private_class_method :comment_help
  end
end
