# typed: strict
# frozen_string_literal: true

require "json"

module Homebrew
  module Bundle
    module MacAppStoreDumper
      sig { void }
      def self.reset!
        @apps = nil
      end

      sig { returns(T::Array[[String, String]]) }
      def self.apps
        @apps ||= T.let(nil, T.nilable(T::Array[[String, String]]))
        @apps ||= if Bundle.mas_installed?
          `mas list 2>/dev/null`.split("\n").map do |app|
            app_details = app.match(/\A\s*(?<id>\d+)\s+(?<name>.*?)\s+\((?<version>[\d.]*)\)\Z/)

            # Only add the application details should we have a valid match.
            # Strip unprintable characters
            if app_details
              name = T.must(app_details[:name])
              [T.must(app_details[:id]), name.gsub(/[[:cntrl:]]|\p{C}/, "")]
            end
          end
        else
          []
        end.compact
      end

      sig { returns(T::Array[Integer]) }
      def self.app_ids
        apps.map { |id, _| id.to_i }
      end

      sig { returns(String) }
      def self.dump
        apps.sort_by { |_, name| name.downcase }.map { |id, name| "mas \"#{name}\", id: #{id}" }.join("\n")
      end
    end
  end
end
