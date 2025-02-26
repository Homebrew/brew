# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Cleanup
      TRIGGERS = %w[cleanup clean cl rm].freeze

      sig { returns(NilClass) }
      def self.run
        cleaned = []

        cleaned += Homebrew::Cmd::Services.kill_orphaned_services
        cleaned += Homebrew::Cmd::Services.remove_unused_service_files

        puts "All #{System.root? ? "root" : "user-space"} services OK, nothing cleaned..." if cleaned.empty?
      end
    end
  end
end
