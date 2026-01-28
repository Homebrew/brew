# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Caskroom < AbstractCommand
      sig { override.returns(String) }
      def self.command_name = "--caskroom"

      cmd_args do
        description <<~EOS
          Display Homebrew's Caskroom path.

          If <cask> is provided, display the location in the Caskroom where <cask>
          would be installed, without any sort of versioned directory as the last path.
        EOS

        named_args :cask
      end

      sig { override.void }
      def run
        if args.named.to_casks.blank?
          puts Cask::Caskroom.path
        else
          args.named.to_casks.each do |cask|
            puts "#{Cask::Caskroom.path}/#{cask.token}"
          end
        end
      end
    end
  end
end
