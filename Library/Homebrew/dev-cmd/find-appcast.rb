# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/appcast"

module Homebrew
  module DevCmd
    class FindAppcast < AbstractCommand
      cmd_args do
        description <<~EOS
          Find the appcast of the app bundle at <app_path>, for use in a cask
          `livecheck` block.

          Checks for a Sparkle `SUFeedURL` and Electron Builder update metadata.
        EOS

        named_args :app_path, number: 1
      end

      sig { override.void }
      def run
        app = Pathname(args.named.fetch(0))
        appcast = Cask::Appcast.find(app)
        if appcast.nil?
          puts "No appcast found."
          return
        end

        puts "Found #{appcast.strategy.inspect} appcast!"
        puts <<~EOS
          livecheck do
            url #{appcast.url.inspect}
            strategy #{appcast.strategy.inspect}
          end
        EOS
      end
    end
  end
end
