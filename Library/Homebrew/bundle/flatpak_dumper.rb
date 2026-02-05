# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakDumper
      sig { void }
      def self.reset!
        @packages = nil
        @packages_with_remotes = nil
        @remote_urls = nil
      end

      sig { returns(T::Hash[String, String]) }
      def self.remote_urls
        @remote_urls ||= T.let(nil, T.nilable(T::Hash[String, String]))

        @remote_urls ||= if Bundle.flatpak_installed?
          flatpak = Bundle.which_flatpak
          output = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
          urls = {}
          output.split("\n").each do |line|
            parts = line.strip.split("\t")
            next if parts.size < 2

            name = parts[0]
            url = parts[1]
            urls[name] = url if name && url
          end
          urls
        else
          {}
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def self.packages_with_remotes
        @packages_with_remotes ||= T.let(nil, T.nilable(T::Array[T::Hash[Symbol, String]]))

        @packages_with_remotes ||= if Bundle.flatpak_installed?
          flatpak = Bundle.which_flatpak
          # List applications with their origin remote
          # Using --app to filter applications only
          # Using --columns=application,origin to get app IDs and their remotes
          output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp
          urls = remote_urls # Get the URL mapping

          packages_list = output.split("\n").filter_map do |line|
            parts = line.strip.split("\t")
            name = parts[0]
            next if parts.empty? || name.nil? || name.empty?

            remote_name = parts[1] || "flathub"
            remote_url = urls[remote_name]

            { name:, remote: remote_name, remote_url: }
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
        # 3-tier remote handling for dump:
        # - Tier 1: flathub → no remote needed
        # - Tier 2: single-app remote (*-origin) → dump with URL only
        # - Tier 3: named shared remote → dump with remote: and url:
        packages_with_remotes.map do |pkg|
          remote_name = pkg[:remote]
          remote_url = pkg[:remote_url]

          if remote_name == "flathub"
            # Tier 1: Don't specify remote for flathub (default)
            "flatpak \"#{pkg[:name]}\""
          elsif remote_name&.end_with?("-origin")
            # Tier 2: Single-app remote - dump with URL only
            if remote_url.present?
              "flatpak \"#{pkg[:name]}\", remote: \"#{remote_url}\""
            else
              # Fallback if URL not available (shouldn't happen for -origin remotes)
              "flatpak \"#{pkg[:name]}\", remote: \"#{remote_name}\""
            end
          elsif remote_url.present?
            # Tier 3: Named shared remote - dump with name and URL
            "flatpak \"#{pkg[:name]}\", remote: \"#{remote_name}\", url: \"#{remote_url}\""
          else
            # Named remote without URL (user-defined or system remote)
            "flatpak \"#{pkg[:name]}\", remote: \"#{remote_name}\""
          end
        end.join("\n")
      end
    end
  end
end
