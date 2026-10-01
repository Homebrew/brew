# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/token_generator"
require "tap"

module Homebrew
  module DevCmd
    class GenerateCaskToken < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate a cask token, filename and header line for an application,
          following the token conventions described in the Cask Cookbook.

          The argument may be either a path to an application bundle
          (e.g. `/Applications/Example App.app`) or the vendor's name for the
          software (e.g. `Example App`).
        EOS

        named_args :app_or_name, number: 1
      end

      sig { override.void }
      def run
        app_name = Cask::TokenGenerator.simplified_app_name(args.named.fetch(0))
        token = Cask::TokenGenerator.token_for(app_name)
        file_name = "#{token}.rb"

        puts "Proposed Simplified App name: #{app_name}" if args.debug?
        puts "Proposed token:               #{token}"
        puts "Proposed file name:           #{file_name}"
        puts "Cask Header Line:             cask \"#{token}\" do"

        warnings = Cask::TokenGenerator.warnings(token)
        duplicate = CoreCaskTap.instance.cask_tokens.include?(token)
        if duplicate
          warnings << "A cask named '#{token}' already exists. " \
                      "Prepend the vendor name if this is not a duplicate."
        end

        warnings.each { |warning| opoo warning }
        # The other warnings are advisory: only a duplicate token needs a rethink.
        Homebrew.failed = true if duplicate
      end
    end
  end
end
