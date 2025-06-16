# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "hardware"

module Homebrew
  module Bundle
    module Skipper
      class << self
        sig { params(entry: Dsl::Entry, silent: T::Boolean).returns(T::Boolean) }
        def skip?(entry, silent: false)
          require "bundle/brew_dumper"

          return true if @failed_taps&.any? do |tap|
            prefix = "#{tap}/"
            entry.name.start_with?(prefix) || entry.options[:full_name]&.start_with?(prefix)
          end

          entry_type_skips = Array(skipped_entries[entry.type])
          return false if entry_type_skips.empty?

          # Check the name or ID particularly for Mac App Store entries where they
          # can have spaces in the names (and the `mas` output format changes on
          # occasion).
          entry_ids = [entry.name, entry.options[:id]&.to_s].compact
          return false unless entry_type_skips.intersect?(entry_ids)

          puts Formatter.warning "Skipping #{entry.name}" unless silent
          true
        end

        def tap_failed!(tap_name)
          @failed_taps ||= []
          @failed_taps << tap_name
        end

        private

        def skipped_entries
          return @skipped_entries if @skipped_entries

          @skipped_entries = {}
          [:brew, :cask, :mas, :tap, :whalebrew].each do |type|
            @skipped_entries[type] =
              ENV["HOMEBREW_BUNDLE_#{type.to_s.upcase}_SKIP"]&.split
          end
          @skipped_entries
        end
      end
    end
  end
end

require "extend/os/bundle/skipper"
