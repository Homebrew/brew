# typed: true
# frozen_string_literal: true

require "cli/parser"
require "commands"

module Homebrew
  # Helper module for printing help output.
  #
  # @api private
  module Help
    # NOTE: Keep the length of vanilla `--help` less than 25 lines!
    #       This is because the default Terminal height is 25 lines. Scrolling sucks
    #       and concision is important. If more help is needed we should start
    #       specialising help like the gem command does.
    # NOTE: Keep lines less than 80 characters! Wrapping is just not cricket.
    HOMEBREW_HELP = <<~EOS
      Example usage:
        brew search TEXT|/REGEX/
        brew info [FORMULA|CASK...]
        brew install FORMULA|CASK...
        brew update
        brew upgrade [FORMULA|CASK...]
        brew uninstall FORMULA|CASK...
        brew list [FORMULA|CASK...]

      Troubleshooting:
        brew config
        brew doctor
        brew install --verbose --debug FORMULA|CASK

      Contributing:
        brew create URL [--no-fetch]
        brew edit [FORMULA|CASK...]

      Further help:
        brew commands
        brew help [COMMAND]
        man brew
        https://docs.brew.sh
    EOS
    private_constant :HOMEBREW_HELP

    def self.help(cmd = nil, empty_argv: false, usage_error: nil, remaining_args: [])
      if cmd.nil?
        # Handle `brew` (no arguments).
        if empty_argv
          $stderr.puts HOMEBREW_HELP
          exit 1
        end

        # Handle `brew (-h|--help|--usage|-?|help)` (no other arguments).
        puts HOMEBREW_HELP
        exit 0
      end

      # Resolve command aliases and find file containing the implementation.
      path = Commands.path(cmd)

      # Display command-specific (or generic) help in response to `UsageError`.
      if usage_error
        $stderr.puts path ? command_help(cmd, path, remaining_args: remaining_args) : HOMEBREW_HELP
        $stderr.puts
        onoe usage_error
        exit 1
      end

      # Resume execution in `brew.rb` for unknown commands.
      return if path.nil?

      # Display help for internal command (or generic help if undocumented).
      puts command_help(cmd, path, remaining_args: remaining_args)
      exit 0
    end

    def self.command_help(cmd, path, remaining_args:)
      # Only some types of commands can have a parser.
      output = if Commands.valid_internal_cmd?(cmd) ||
                  Commands.valid_internal_dev_cmd?(cmd) ||
                  Commands.external_ruby_v2_cmd_path(cmd)
        parser_help(path, remaining_args: remaining_args)
      end

      output ||= comment_help(path)

      output ||= if output.blank?
        opoo "No help text in: #{path}" if Homebrew::EnvConfig.developer?
        HOMEBREW_HELP
      end

      output
    end
    private_class_method :command_help

    def self.parser_help(path, remaining_args:)
      # Let OptionParser generate help text for commands which have a parser.
      cmd_parser = CLI::Parser.from_cmd_path(path)
      return unless cmd_parser

      # Try parsing arguments here in order to show formula options in help output.
      cmd_parser.parse(remaining_args, ignore_invalid_options: true)
      cmd_parser.generate_help_text
    end
    private_class_method :parser_help

    def self.command_help_lines(path)
      path.read
          .lines
          .grep(/^#:/)
          .map { |line| line.slice(2..-1).delete_prefix("  ") }
    end
    private_class_method :command_help_lines

    def self.comment_help(path)
      # Otherwise read #: lines from the file.
      help_lines = command_help_lines(path)
      return if help_lines.blank?

      Formatter.format_help_text(help_lines.join, width: COMMAND_DESC_WIDTH)
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
