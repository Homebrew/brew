# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakRemoteDumper
      sig { void }
      def self.reset!
        @remotes = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, String]]))
        @remote_names = T.let(nil, T.nilable(T::Array[String]))
      end

      sig { returns(T::Array[String]) }
      def self.remote_names
        @remote_names ||= T.let(nil, T.nilable(T::Array[String]))
        @remote_names ||= remotes.map { |remote| T.must(remote[:name]) }
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def self.remotes
        @remotes ||= T.let(nil, T.nilable(T::Array[T::Hash[Symbol, String]]))
        return @remotes = [] if OS.mac?

        @remotes ||= if Bundle.flatpak_installed?
          flatpak = Bundle.which_flatpak
          # List remotes with columns: name and URL
          # Using --system to only show system remotes
          output = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
          remotes_list = output.split("\n").filter_map do |line|
            parts = line.strip.split("\t")
            name = parts[0]
            next if parts.empty? || name.nil? || name.empty?
            # Skip header line if present
            next if name == "Name"

            { name: name, url: parts[1] || "" }
          end
          remotes_list.sort_by { |remote| remote[:name] }
        else
          []
        end
      end

      sig { returns(String) }
      def self.dump
        remotes.map do |remote|
          # Always include URL for flatpak remotes
          "flatpak_remote \"#{remote[:name]}\", \"#{remote[:url]}\""
        end.join("\n")
      end
    end
  end
end
