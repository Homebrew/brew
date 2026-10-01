# typed: strict
# frozen_string_literal: true

require "utils/output"

module Homebrew
  module Bundle
    module Skipper
      extend Utils::Output::Mixin

      class << self
        sig { params(entry: Dsl::Entry).returns(T::Boolean) }
        def skip?(entry)
          require "bundle/brew"

          if (reason = unsupported_reason(entry))
            opoo_without_github_actions_annotation "Skipping #{entry.type} #{entry.name} (#{reason})"
            return true
          end

          full_name = entry.options[:full_name]
          return true if @failed_taps&.any? do |tap|
            prefix = "#{tap}/"
            entry.name.start_with?(prefix) || (full_name.is_a?(String) && full_name.start_with?(prefix))
          end

          entry_type_skips = Array(skipped_entries[entry.type])
          return false if entry_type_skips.empty?

          # Check the name or ID particularly for Mac App Store entries where they
          # can have spaces in the names (and the `mas` output format changes on
          # occasion).
          entry_ids = [entry.name, entry.options[:id]&.to_s].compact
          return false unless entry_type_skips.intersect?(entry_ids)

          opoo_without_github_actions_annotation "Skipping #{entry.name}"
          true
        end

        sig { params(tap_name: String).void }
        def tap_failed!(tap_name)
          @failed_taps ||= T.let([], T.nilable(T::Array[String]))
          @failed_taps << tap_name
        end

        sig { params(failed_taps: T.nilable(T::Array[String])).returns(T.nilable(T::Array[String])) }
        attr_writer :failed_taps

        sig {
          params(skipped_entries: T.nilable(T::Hash[Symbol, T.nilable(T::Array[String])]))
            .returns(T.nilable(T::Hash[Symbol, T.nilable(T::Array[String])]))
        }
        attr_writer :skipped_entries

        private

        sig { params(_entry: Dsl::Entry).returns(T.nilable(String)) }
        def unsupported_reason(_entry) = nil

        sig { returns(T::Hash[Symbol, T.nilable(T::Array[String])]) }
        def skipped_entries
          return @skipped_entries if @skipped_entries

          @skipped_entries ||= T.let({}, T.nilable(T::Hash[Symbol, T.nilable(T::Array[String])]))
          [:brew, :cask, :mas, :tap, :flatpak, :winget].each do |type|
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
