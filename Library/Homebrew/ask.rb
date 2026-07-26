# typed: strict
# frozen_string_literal: true

require "io/console"
require "utils/output"

module Homebrew
  module Ask
    extend Utils::Output::Mixin

    sig { params(action: String).returns(T::Boolean) }
    def self.confirm?(action:)
      return false if !$stdin.tty? || !$stdout.tty?

      safe_action = action.gsub(/[^a-zA-Z0-9 _\-]/, "")
      ohai "Do you want to proceed with the #{safe_action}? [y/n]"
      loop do
        result = begin
          $stdin.getch
        rescue Interrupt
          exit 1
        end
        exit 1 unless result

        result = result.chomp.strip.downcase
        if result == "y"
          return true
        # N, Escape, Ctrl-C and Ctrl-D.
        elsif ["n", "\e", "\u0003", "\u0004"].include?(result)
          exit 1
        else
          puts "Invalid input. Please press 'y' to proceed, or 'n' to abort."
        end
      end
    end
  end
end
