# typed: strict
# frozen_string_literal: true

require "json"

module Homebrew
  module Bundle
    module TapDumper
      sig { void }
      def self.reset!
        @taps = nil
      end

      sig { returns(String) }
      def self.dump
        taps.map do |tap|
          remote = if tap.custom_remote? && (tap_remote = tap.remote)
            if (api_token = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", false).presence)
              # Replace the API token in the remote URL with interpolation.
              # Rubocop's warning here is wrong; we intentionally want to not
              # evaluate this string until the Brewfile is evaluated.
              # rubocop:disable Lint/InterpolationCheck
              tap_remote = tap_remote.gsub api_token, '#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}'
              # rubocop:enable Lint/InterpolationCheck
            end
            ", \"#{tap_remote}\""
          end
          "tap \"#{tap.name}\"#{remote}"
        end.sort.uniq.join("\n")
      end

      sig { returns(T::Array[String]) }
      def self.tap_names
        taps.map(&:name)
      end

      sig { returns(T::Array[Tap]) }
      private_class_method def self.taps
        @taps ||= T.let(nil, T.nilable(T::Array[Tap]))
        @taps ||= begin
          require "tap"
          Tap.select(&:installed?).to_a
        end
      end
    end
  end
end
