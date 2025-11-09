# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakDumper
      sig { void }
      def self.reset!
        @packages = nil
        @packages_with_remotes = nil
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def self.packages_with_remotes
        @packages_with_remotes ||= T.let(nil, T.nilable(T::Array[T::Hash[Symbol, String]]))
        return @packages_with_remotes = [] if OS.mac?

        @packages_with_remotes ||= if Bundle.flatpak_installed?
          flatpak = Bundle.which_flatpak
          # List applications with their origin remote
          # Using --app to filter applications only
          # Using --columns=application,origin to get app IDs and their remotes
          output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp
          packages_list = output.split("\n").filter_map do |line|
            parts = line.strip.split("\t")
            name = parts[0]
            next if parts.empty? || name.nil? || name.empty?

            { name: name, remote: parts[1] || "flathub" }
          end
          packages_list.sort_by { |pkg| pkg[:name] }
        else
          []
        end
      end

      sig { returns(T::Array[String]) }
      def self.packages
        @packages ||= T.let(nil, T.nilable(T::Array[String]))
        @packages ||= packages_with_remotes.map { |pkg| T.must(pkg[:name]) }
      end

      sig { returns(String) }
      def self.dump
        packages_with_remotes.map do |pkg|
          if pkg[:remote] == "flathub"
            # Don't specify remote for flathub (default)
            "flatpak \"#{pkg[:name]}\""
          else
            # Specify remote for non-flathub packages
            "flatpak \"#{pkg[:name]}\", remote: \"#{pkg[:remote]}\""
          end
        end.join("\n")
      end
    end
  end
end
