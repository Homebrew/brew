# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Commands
      module Services
        sig { params(args: String, global: T::Boolean, file: T.nilable(String)).void }
        def self.run(*args, global:, file:)
          raise UsageError, "invalid `brew bundle services` arguments" if args.length != 1

          parsed_entries = Brewfile.read(global:, file:).entries

          subcommand = args.first
          case subcommand
          when "run"
            Homebrew::Bundle::Services.run(parsed_entries)
          when "stop"
            Homebrew::Bundle::Services.stop(parsed_entries)
          else
            raise UsageError, "unknown bundle services subcommand: #{subcommand}"
          end
        end
      end
    end
  end
end
