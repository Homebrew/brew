# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "json"

module Homebrew
  module Bundle
    module MacAppStoreDumper
      def self.reset!
        @apps = nil
      end

      def self.apps
        @apps ||= if Bundle.mas_installed?
          `mas list 2>/dev/null`.split("\n").map do |app|
            app_details = app.match(/\A(?<id>\d+)\s+(?<name>.*?)\s+\((?<version>[\d.]*)\)\Z/)

            # Only add the application details should we have a valid match.
            # Strip unprintable characters
            if app_details
              name = T.must(app_details[:name])
              [app_details[:id], name.gsub(/[[:cntrl:]]|[\p{C}]/, "")]
            end
          end
        else
          []
        end.compact
      end

      def self.app_ids
        apps.map { |id, _| id.to_i }
      end

      def self.dump
        apps.sort_by { |_, name| name.downcase }.map { |id, name| "mas \"#{name}\", id: #{id}" }.join("\n")
      end
    end
  end
end
