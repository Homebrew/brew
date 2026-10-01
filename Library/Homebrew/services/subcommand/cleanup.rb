# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class CleanupSubcommand < Homebrew::AbstractSubcommand
        subcommand_args aliases: %w[clean cl rm] do
          usage_banner <<~EOS
            [`sudo`] `brew services cleanup`:
            Remove all unused services.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          cleaned = []

          cleaned += Homebrew::Services::Cli.kill_orphaned_services
          cleaned += Homebrew::Services::Cli.remove_unused_service_files

          return if cleaned.any?

          service_type = if Homebrew::Services::System.root?
            "root"
          else
            "user-space"
          end
          puts "All #{service_type} services OK, nothing cleaned..."
        end
      end
    end
  end
end
