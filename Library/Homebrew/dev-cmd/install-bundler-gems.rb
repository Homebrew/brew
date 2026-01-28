# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module DevCmd
    class InstallBundlerGems < AbstractCommand
      cmd_args do
        description <<~EOS
          Install Homebrew's Bundler gems.
        EOS
        comma_array "--groups",
                    description: "Installs the specified comma-separated list of gem groups (default: last used). " \
                                 "Replaces any previously installed groups."
        comma_array "--add-groups",
                    description: "Installs the specified comma-separated list of gem groups, " \
                                 "in addition to those already installed."

        conflicts "--groups", "--add-groups"

        named_args :none
      end

      sig { override.void }
      def run
        groups = args.groups || args.add_groups || []

        if groups.delete("all")
          groups |= Homebrew.valid_gem_groups
        elsif args.groups # if we have been asked to replace
          Homebrew.forget_user_gem_groups!
        end

        Homebrew.install_bundler_gems!(groups:)
      end
    end
  end
end
