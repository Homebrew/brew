# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # The `Livecheck::Strategy` module contains the various strategies as well
    # as some general-purpose methods for working with them. Within the context
    # of the `brew livecheck` command, strategies are established procedures
    # for finding new software versions at a given source.
    #
    # @api private
    module Strategy
      extend Utils::Curl

      module_function

      # {Strategy} priorities informally range from 1 to 10, where 10 is the
      # highest priority. 5 is the default priority because it's roughly in
      # the middle of this range. Strategies with a priority of 0 (or lower)
      # are ignored.
      DEFAULT_PRIORITY = 5

      # cURL's default `--connect-timeout` value can be up to two minutes, so
      # we need to use a more reasonable duration (in seconds) to avoid a
      # lengthy wait when a connection can't be established.
      CURL_CONNECT_TIMEOUT = 10

      # cURL does not set a default `--max-time` value, so we provide a value
      # to ensure cURL will time out in a reasonable amount of time.
      CURL_MAX_TIME = CURL_CONNECT_TIMEOUT + 5

      # The `curl` process will sometimes hang indefinitely (despite setting
      # the `--max-time` argument) and it needs to be quit for livecheck to
      # continue. This value is used to set the `timeout` argument on
      # `Utils::Curl` method calls in {Strategy}.
      CURL_PROCESS_TIMEOUT = CURL_MAX_TIME + 5

      # The maximum number of redirections that `curl` should allow.
      MAX_REDIRECTIONS = 5

      # This value is passed to `#parse_curl_output` to ensure that the limit
      # for the number of responses it will parse corresponds to the maximum
      # number of responses in this context. The `+ 1` here accounts for the
      # situation where there are exactly `MAX_REDIRECTIONS` number of
      # redirections, followed by a final `200 OK` response.
      MAX_PARSE_ITERATIONS = MAX_REDIRECTIONS + 1

      # Baseline `curl` arguments used in {Strategy} methods.
      DEFAULT_CURL_ARGS = [
        # Follow redirections to handle mirrors, relocations, etc.
        "--location",
        "--max-redirs", MAX_REDIRECTIONS.to_s,
        # Avoid progress bar text, so we can reliably identify `curl` error
        # messages in output
        "--silent"
      ].freeze

      # `curl` arguments used in `Strategy#page_content` method.
      PAGE_CONTENT_CURL_ARGS = ([
        "--compressed",
        # Include HTTP response headers in output, so we can identify the
        # final URL after any redirections
        "--include",
      ] + DEFAULT_CURL_ARGS).freeze

      # Baseline `curl` options used in {Strategy} methods.
      DEFAULT_CURL_OPTIONS = {
        print_stdout:    false,
        print_stderr:    false,
        debug:           false,
        verbose:         false,
        timeout:         CURL_PROCESS_TIMEOUT,
        connect_timeout: CURL_CONNECT_TIMEOUT,
        max_time:        CURL_MAX_TIME,
        retries:         0,
      }.freeze

      # A regex used to identify a tarball extension at the end of a string.
      TARBALL_EXTENSION_REGEX = /
        \.t
        (?:ar(?:\.(?:bz2|gz|lz|lzma|lzo|xz|Z|zst))?|
        b2|bz2?|z2|az|gz|lz|lzma|xz|Z|aZ|zst)
        $
      /ix.freeze

      # An error message to use when a `strategy` block returns a value of
      # an inappropriate type.
      INVALID_BLOCK_RETURN_VALUE_MSG = "Return value of a strategy block must be a string or array of strings."

      # Creates and/or returns a `@strategies` `Hash`, which maps a snake
      # case strategy name symbol (e.g. `:page_match`) to the associated
      # strategy.
      #
      # At present, this should only be called after tap strategies have been
      # loaded, otherwise livecheck won't be able to use them.
      # @return [Hash]
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def strategies
        return @strategies if defined? @strategies

        @strategies = {}
        Strategy.constants.sort.each do |const_symbol|
          constant = Strategy.const_get(const_symbol)
          next unless constant.is_a?(Class)

          key = Utils.underscore(const_symbol).to_sym
          @strategies[key] = constant
        end
        @strategies
      end
      private_class_method :strategies

      # Returns the strategy that corresponds to the provided `Symbol` (or
      # `nil` if there is no matching strategy).
      #
      # @param symbol [Symbol, nil] the strategy name in snake case as a
      #   `Symbol` (e.g. `:page_match`)
      # @return [Class, nil]
      sig { params(symbol: T.nilable(Symbol)).returns(T.untyped) }
      def from_symbol(symbol)
        strategies[symbol] if symbol.present?
      end

      # Returns an array of strategies that apply to the provided URL.
      #
      # @param url [String] the URL to check for matching strategies
      # @param livecheck_strategy [Symbol] a strategy symbol from the
      #   `livecheck` block
      # @param url_provided [Boolean] whether a url is provided in the
      #   `livecheck` block
      # @param regex_provided [Boolean] whether a regex is provided in the
      #   `livecheck` block
      # @param block_provided [Boolean] whether a `strategy` block is provided
      #   in the `livecheck` block
      # @return [Array]
      sig {
        params(
          url:                String,
          livecheck_strategy: T.nilable(Symbol),
          url_provided:       T::Boolean,
          regex_provided:     T::Boolean,
          block_provided:     T::Boolean,
        ).returns(T::Array[T.untyped])
      }
      def from_url(url, livecheck_strategy: nil, url_provided: false, regex_provided: false, block_provided: false)
        usable_strategies = strategies.select do |strategy_symbol, strategy|
          if strategy == PageMatch
            # Only treat the strategy as usable if the `livecheck` block
            # contains a regex and/or `strategy` block
            next if !regex_provided && !block_provided
          elsif [Json, Xml, Yaml].include?(strategy)
            # Only treat the strategy as usable if the `livecheck` block
            # specifies the strategy and contains a `strategy` block
            next if (livecheck_strategy != strategy_symbol) || !block_provided
          elsif strategy.const_defined?(:PRIORITY) &&
                !strategy.const_get(:PRIORITY).positive? &&
                livecheck_strategy != strategy_symbol
            # Ignore strategies with a priority of 0 or lower, unless the
            # strategy is specified in the `livecheck` block
            next
          end

          strategy.respond_to?(:match?) && strategy.match?(url)
        end.values

        # Sort usable strategies in descending order by priority, using the
        # DEFAULT_PRIORITY when a strategy doesn't contain a PRIORITY constant
        usable_strategies.sort_by do |strategy|
          (strategy.const_defined?(:PRIORITY) ? -strategy.const_get(:PRIORITY) : -DEFAULT_PRIORITY)
        end
      end

      # Collects HTTP response headers, starting with the provided URL.
      # Redirections will be followed and all the response headers are
      # collected into an array of hashes.
      #
      # @param url [String] the URL to fetch
      # @param homebrew_curl [Boolean] whether to use brewed curl with the URL
      # @return [Array]
      sig { params(url: String, homebrew_curl: T::Boolean).returns(T::Array[T::Hash[String, String]]) }
      def self.page_headers(url, homebrew_curl: false)
        headers = []

        [:default, :browser].each do |user_agent|
          begin
            parsed_output = curl_headers(
              "--max-redirs",
              MAX_REDIRECTIONS.to_s,
              url,
              wanted_headers:    ["location", "content-disposition"],
              use_homebrew_curl: homebrew_curl,
              user_agent:        user_agent,
              **DEFAULT_CURL_OPTIONS,
            )
          rescue ErrorDuringExecution
            next
          end

          parsed_output[:responses].each { |response| headers << response[:headers] }
          break if headers.present?
        end

        headers
      end

      # Fetches the content at the URL and returns a hash containing the
      # content and, if there are any redirections, the final URL.
      # If `curl` encounters an error, the hash will contain a `:messages`
      # array with the error message instead.
      #
      # @param url [String] the URL of the content to check
      # @param homebrew_curl [Boolean] whether to use brewed curl with the URL
      # @return [Hash]
      sig { params(url: String, homebrew_curl: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def self.page_content(url, homebrew_curl: false)
        stderr = T.let(nil, T.nilable(String))
        [:default, :browser].each do |user_agent|
          stdout, stderr, status = curl_output(
            *PAGE_CONTENT_CURL_ARGS, url,
            **DEFAULT_CURL_OPTIONS,
            use_homebrew_curl: homebrew_curl,
            user_agent:        user_agent
          )
          next unless status.success?

          # stdout contains the header information followed by the page content.
          # We use #scrub here to avoid "invalid byte sequence in UTF-8" errors.
          output = stdout.scrub

          # Separate the head(s)/body and identify the final URL (after any
          # redirections)
          parsed_output = parse_curl_output(output, max_iterations: MAX_PARSE_ITERATIONS)
          final_url = curl_response_last_location(parsed_output[:responses], absolutize: true, base_url: url)

          data = { content: parsed_output[:body] }
          data[:final_url] = final_url if final_url.present? && final_url != url
          return data
        end

        error_msgs = stderr&.scan(/^curl:.+$/)
        { messages: error_msgs.presence || ["cURL failed without a detectable error"] }
      end

      # Handles the return value from a `strategy` block in a `livecheck`
      # block.
      #
      # @param value [] the return value from a `strategy` block
      # @return [Array]
      sig { params(value: T.untyped).returns(T::Array[String]) }
      def self.handle_block_return(value)
        case value
        when String
          [value]
        when Array
          value.compact.uniq
        when nil
          []
        else
          raise TypeError, INVALID_BLOCK_RETURN_VALUE_MSG
        end
      end
    end
  end
end

require_relative "strategy/apache"
require_relative "strategy/bitbucket"
require_relative "strategy/cpan"
require_relative "strategy/electron_builder"
require_relative "strategy/extract_plist"
require_relative "strategy/git"
require_relative "strategy/github_latest"
require_relative "strategy/github_releases"
require_relative "strategy/gnome"
require_relative "strategy/gnu"
require_relative "strategy/hackage"
require_relative "strategy/header_match"
require_relative "strategy/json"
require_relative "strategy/launchpad"
require_relative "strategy/npm"
require_relative "strategy/page_match"
require_relative "strategy/pypi"
require_relative "strategy/sourceforge"
require_relative "strategy/sparkle"
require_relative "strategy/xml"
require_relative "strategy/xorg"
require_relative "strategy/yaml"
