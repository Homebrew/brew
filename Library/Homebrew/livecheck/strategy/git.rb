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
            uri = Addressable::URI.parse url
          rescue Addressable::URI::InvalidURIError
            return url
          end

          host = uri.host
          path = uri.path
          return url if host.nil? || path.nil?

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

        # Fetches a remote Git repository's tags using `git ls-remote --tags`
        # and parses the command's output. If a regex is provided, it will be
        # used to filter out any tags that don't match it.
        #
        # @param url [String] the URL of the Git repository to check
        # @param regex [Regexp] the regex to use for filtering tags
        # @return [Hash]
        sig { params(url: String, regex: T.nilable(Regexp)).returns(T::Hash[Symbol, T.untyped]) }
        def self.tag_info(url, regex = nil)
          stdout, stderr, _status = system_command(
            "git",
            args:         ["ls-remote", "--tags", url],
            env:          { "GIT_TERMINAL_PROMPT" => "0" },
            print_stdout: false,
            print_stderr: false,
            debug:        false,
            verbose:      false,
          )

          tags_data = { tags: [] }
          tags_data[:messages] = stderr.split("\n") if stderr.present?
          return tags_data if stdout.blank?

          # Isolate tag strings and filter by regex
          tags = stdout.gsub(%r{^.*\trefs/tags/|\^{}$}, "").split("\n").uniq.sort
          tags.select! { |t| regex.match?(t) } if regex
          tags_data[:tags] = tags

          tags_data
        end

        # Identify versions from tag strings using a provided regex or the
        # `DEFAULT_REGEX`. The regex is expected to use a capture group around
        # the version text.
        #
        # @param tags [Array] the tags to identify versions from
        # @param regex [Regexp, nil] a regex to identify versions
        # @return [Array]
        sig {
          params(
            tags:  T::Array[String],
            regex: T.nilable(Regexp),
            block: T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_tags(tags, regex = nil, &block)
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

          tags.filter_map do |tag|
            if regex
              # Use the first capture group (the version)
              # This code is not typesafe unless the regex includes a capture group
              T.unsafe(tag.scan(regex).first)&.first
            else
              # Remove non-digits from the start of the tag and use that as the
              # version text
              tag[DEFAULT_REGEX, 1]
            end
          end.uniq
        end

        # Checks the Git tags for new versions. When a regex isn't provided,
        # this strategy simply removes non-digits from the start of tag
        # strings and parses the remaining text as a {Version}.
        #
        # @param url [String] the URL of the Git repository to check
        # @param regex [Regexp, nil] a regex used for matching versions
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            url:     String,
            regex:   T.nilable(Regexp),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }

          tags_data = tag_info(url, regex)
          tags = tags_data[:tags]

          if tags_data.key?(:messages)
            match_data[:messages] = tags_data[:messages]
            return match_data if tags.blank?
          end

          versions_from_tags(tags, regex, &block).each do |version_text|
            match_data[:matches][version_text] = Version.new(version_text)
          rescue TypeError
            next
          end

          match_data
        end
      end
    end
  end
end
