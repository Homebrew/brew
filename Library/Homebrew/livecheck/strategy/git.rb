# typed: strict
# frozen_string_literal: true

require "addressable"
require "livecheck/strategic"
require "system_command"

module Homebrew
  module Livecheck
    module Strategy
      # The {Git} strategy identifies versions of software in a Git repository
      # by checking the tags using `git ls-remote --tags`.
      #
      # Livecheck has historically prioritized the {Git} strategy over others
      # and this behavior was continued when the priority setup was created.
      # This is partly related to Livecheck checking formula URLs in order of
      # `head`, `stable` and then `homepage`. The higher priority here may
      # be removed (or altered) in the future if we reevaluate this particular
      # behavior.
      #
      # This strategy does not have a default regex. Instead, it simply removes
      # any non-digit text from the start of tags and parses the rest as a
      # {Version}. This works for some simple situations but even one unusual
      # tag can cause a bad result. It's better to provide a regex in a
      # `livecheck` block, so `livecheck` only matches what we really want.
      #
      # @api public
      class Git
        extend Strategic
        extend SystemCommand::Mixin

        # Used to cache processed URLs, to avoid duplicating effort.
        @processed_urls = T.let({}, T::Hash[String, String])

        # The priority of the strategy on an informal scale of 1 to 10 (from
        # lowest to highest).
        PRIORITY = 8

        # The regex used to extract tags from `git ls-remote --tags` output.
        TAG_REGEX = %r{^\h+\s+refs/tags/(.+?)(?:\^{})?$}

        # The default regex used to naively identify versions from tags when a
        # regex isn't provided.
        DEFAULT_REGEX = /\D*(.+)/

        GITEA_INSTANCES = T.let(%w[
          codeberg.org
          gitea.com
          opendev.org
          tildegit.org
        ].freeze, T::Array[String])
        private_constant :GITEA_INSTANCES

        GOGS_INSTANCES = T.let(%w[
          lolg.it
        ].freeze, T::Array[String])
        private_constant :GOGS_INSTANCES

        # Processes and returns the URL used by livecheck.
        sig { params(url: String).returns(String) }
        def self.preprocess_url(url)
          processed_url = @processed_urls[url]
          return processed_url if processed_url

          begin
            uri = Addressable::URI.parse(url)
          rescue Addressable::URI::InvalidURIError
            return url
          end

          host = uri.host
          path = uri.path
          return url if host.nil? || path.blank?

          host = "github.com" if host == "github.s3.amazonaws.com"
          path = path.delete_prefix("/").delete_suffix(".git")
          scheme = uri.scheme

          if host == "github.com"
            return url if path.match? %r{/releases/latest/?$}

            owner, repo = path.delete_prefix("downloads/").split("/")
            processed_url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
          elsif GITEA_INSTANCES.include?(host)
            return url if path.match? %r{/releases/latest/?$}

            owner, repo = path.split("/")
            processed_url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
          elsif GOGS_INSTANCES.include?(host)
            owner, repo = path.split("/")
            processed_url = "#{scheme}://#{host}/#{owner}/#{repo}.git"
          # sourcehut
          elsif host == "git.sr.ht"
            owner, repo = path.split("/")
            processed_url = "#{scheme}://#{host}/#{owner}/#{repo}"
          # GitLab (gitlab.com or self-hosted)
          elsif path.include?("/-/archive/")
            processed_url = url.sub(%r{/-/archive/.*$}i, ".git")
          end

          if processed_url && (processed_url != url)
            @processed_urls[url] = processed_url
          else
            url
          end
        end

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          url = preprocess_url(url)
          (DownloadStrategyDetector.detect(url) <= GitDownloadStrategy) == true
        end

        # Runs `git ls-remote --tags` with the provided URL and returns a hash
        # containing the `stdout` content or any errors from `stderr`.
        #
        # @param url [String] the URL of the Git repository to check
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.any(String, T::Array[String])]) }
        def self.ls_remote_tags(url)
          stdout, stderr, _status = system_command(
            "git",
            args:         ["ls-remote", "--tags", url],
            env:          { "GIT_TERMINAL_PROMPT" => "0" },
            print_stdout: false,
            print_stderr: false,
            debug:        false,
            verbose:      false,
          ).to_a

          data = {}
          data[:content] = stdout.clone if stdout.present?
          data[:messages] = stderr.split("\n") if stderr.present?

          data
        end

        # Parse tags from `git ls-remote --tags` output.
        #
        # @param content [String] Git output to parse for tags
        # @return [Array]
        sig { params(content: String).returns(T::Array[String]) }
        def self.tags_from_content(content)
          content.scan(TAG_REGEX).flatten.uniq
        end

        # Identify versions from `git ls-remote --tags` output using a provided
        # regex or the `DEFAULT_REGEX`. The regex is expected to use a capture
        # group around the version text.
        #
        # @param content [String] the content to check
        # @param regex [Regexp, nil] a regex to identify versions
        # @return [Array]
        sig {
          params(
            content: String,
            regex:   T.nilable(Regexp),
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex = nil, &block)
          tags = tags_from_content(content)
          return [] if tags.empty?

          if block
            block_return_value = if regex.present?
              yield(tags, regex)
            elsif block.arity == 2
              yield(tags, DEFAULT_REGEX)
            else
              yield(tags)
            end
            return Strategy.handle_block_return(block_return_value)
          end

          match_regex = regex || DEFAULT_REGEX
          tags.filter_map { |tag| tag[match_regex, 1] }.uniq
        end

        # Checks the Git tags for new versions. When a regex isn't provided,
        # this strategy simply removes non-digits from the start of tag
        # strings and parses the remaining text as a {Version}.
        #
        # @param url [String] the URL of the Git repository to check
        # @param regex [Regexp, nil] a regex for matching versions in content
        # @param provided_content [String, nil] content to check instead of
        #   fetching
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:              String,
            regex:            T.nilable(Regexp),
            provided_content: T.nilable(String),
            options:          Options,
            block:            T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, provided_content: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }
          return match_data if url.blank?

          content = if provided_content.is_a?(String)
            match_data[:cached] = true
            provided_content
          else
            match_data.merge!(ls_remote_tags(url))
            match_data[:content]
          end
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          rescue TypeError
            next
          end

          match_data
        end
      end
    end
  end
end
