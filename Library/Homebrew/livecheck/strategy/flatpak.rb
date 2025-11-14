# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"
require "system_command"

module Homebrew
  module Livecheck
    module Strategy
      # The {Flatpak} strategy identifies versions of software in a Flatpak
      # remote repository by querying the remote using `flatpak remote-info`.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :flatpak` in a `livecheck` block to apply it.
      #
      # This strategy requires the cask to have a `flatpak` stanza and will
      # query the configured remote (or "flathub" by default) for version
      # information.
      #
      # @api public
      class Flatpak
        extend Strategic
        extend SystemCommand::Mixin

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {Flatpak} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The {Flatpak} strategy does not match URLs, as version information
        # comes from flatpak remotes rather than a URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(_url)
          false
        end

        # Checks the Flatpak remote for new versions by querying
        # `flatpak remote-info --system <remote> <app-id>` and parsing
        # the version from the output.
        #
        # @param cask [Cask::Cask] the cask to check for version information
        # @param url [String, nil] not used by this strategy (for compatibility)
        # @param regex [Regexp, nil] a regex for filtering/parsing versions
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            cask:    Cask::Cask,
            url:     T.nilable(String),
            regex:   T.nilable(Regexp),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(cask:, url: nil, regex: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }

          # Find flatpak artifact in cask
          flatpak_artifact = cask.artifacts.find { |a| a.is_a?(Cask::Artifact::Flatpak) }
          unless flatpak_artifact
            match_data[:messages] = ["Cask does not have a flatpak stanza"]
            return match_data
          end

          app_id = flatpak_artifact.app_id
          remote = flatpak_artifact.send(:remote)

          # Check if flatpak command exists
          unless which("flatpak")
            match_data[:messages] = ["flatpak command not found"]
            return match_data
          end

          # Query flatpak remote for version information
          stdout, stderr, status = system_command(
            "flatpak",
            args:         ["remote-info", "--system", remote, app_id],
            print_stdout: false,
            print_stderr: false,
          ).to_a

          unless status.success?
            error_message = stderr.present? ? stderr.split("\n").first : "Failed to query flatpak remote"
            match_data[:messages] = [error_message]
            return match_data
          end

          # Parse version from output
          version_line = stdout.lines.find { |line| line.match?(/^\s*Version:/) }
          unless version_line
            match_data[:messages] = ["No version information found in flatpak remote-info output"]
            return match_data
          end

          version_text = version_line.split(":", 2)[1]&.strip
          unless version_text
            match_data[:messages] = ["Failed to parse version from output"]
            return match_data
          end

          # If a block is provided, use it to process the version
          if block
            block_return_value = regex.present? ? yield(version_text, regex) : yield(version_text)
            versions = Strategy.handle_block_return(block_return_value)
            versions.each do |v|
              match_data[:matches][v] = Version.new(v)
            rescue TypeError
              next
            end
          elsif regex
            # Apply regex to version text if provided
            match = version_text.match(regex)
            if match&.captures&.any?
              version = match.captures.first
              match_data[:matches][version] = Version.new(version)
            end
          else
            # Use version text as-is
            match_data[:matches][version_text] = Version.new(version_text)
          end

          match_data
        rescue TypeError
          match_data
        end
      end
    end
  end
end
