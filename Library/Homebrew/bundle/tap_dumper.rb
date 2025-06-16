# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "json"

module Homebrew
  module Bundle
    module TapDumper
      def self.reset!
        @taps = nil
      end

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

      def self.tap_names
        taps.map(&:name)
      end

      private_class_method def self.taps
        @taps ||= begin
          require "tap"
          Tap.select(&:installed?).to_a
        end
      end
    end
  end
end
