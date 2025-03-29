# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class TapChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :tap
        PACKAGE_TYPE_NAME = "Tap"

        def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
          requested_taps = format_checkable(entries)
          return [] if requested_taps.empty?

          require "bundle/tap_dumper"
          current_taps = Homebrew::Bundle::TapDumper.tap_names
          (requested_taps - current_taps).map { |entry| "Tap #{entry} needs to be tapped." }
        end
      end
    end
  end
end
