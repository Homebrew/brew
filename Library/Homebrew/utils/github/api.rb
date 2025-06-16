# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "system_command"

module GitHub
  def self.pat_blurb(scopes = ALL_SCOPES)
    require "utils/formatter"
    require "utils/shell"
    <<~EOS
      Create a GitHub personal access token:
        #{Formatter.url(
          "https://github.com/settings/tokens/new?scopes=#{scopes.join(",")}&description=Homebrew",
        )}
      #{Utils::Shell.set_variable_in_profile("HOMEBREW_GITHUB_API_TOKEN", "your_token_here")}
    EOS
  end

  API_URL = "https://api.github.com"
  API_MAX_PAGES = 50
  private_constant :API_MAX_PAGES
  API_MAX_ITEMS = 5000
  private_constant :API_MAX_ITEMS
  PAGINATE_RETRY_COUNT = 3
  private_constant :PAGINATE_RETRY_COUNT

  CREATE_GIST_SCOPES = ["gist"].freeze
  CREATE_ISSUE_FORK_OR_PR_SCOPES = ["repo"].freeze
  CREATE_WORKFLOW_SCOPES = ["workflow"].freeze
  ALL_SCOPES = (CREATE_GIST_SCOPES + CREATE_ISSUE_FORK_OR_PR_SCOPES + CREATE_WORKFLOW_SCOPES).freeze
  private_constant :ALL_SCOPES
  GITHUB_PERSONAL_ACCESS_TOKEN_REGEX = /^(?:[a-f0-9]{40}|(?:gh[pousr]|github_pat)_\w{36,251})$/
  private_constant :GITHUB_PERSONAL_ACCESS_TOKEN_REGEX

  # Helper functions for accessing the GitHub API.
  #
  # @api internal
  module API
    extend SystemCommand::Mixin

    # Generic API error.
    class Error < RuntimeError
      attr_reader :github_message
    end

    # Error when the requested URL is not found.
    class HTTPNotFoundError < Error
      def initialize(github_message)
        @github_message = github_message
        super
      end
    end

    # Error when the API rate limit is exceeded.
    class RateLimitExceededError < Error
      def initialize(reset, github_message)
        @github_message = github_message
        new_pat_message = ", or:\n#{GitHub.pat_blurb}" if API.credentials.blank?
        super <<~EOS
          GitHub API Error: #{github_message}
          Try again in #{pretty_ratelimit_reset(reset)}#{new_pat_message}
        EOS
      end

      def pretty_ratelimit_reset(reset)
        pretty_duration(Time.at(reset) - Time.now)
      end
    end

    GITHUB_IP_ALLOWLIST_ERROR = Regexp.new("Although you appear to have the correct authorization credentials, " \
                                           "the `(.+)` organization has an IP allow list enabled, " \
                                           "and your IP address is not permitted to access this resource").freeze

    NO_CREDENTIALS_MESSAGE = <<~MESSAGE.freeze
      No GitHub credentials found in macOS Keychain, GitHub CLI or the environment.
      #{GitHub.pat_blurb}
    MESSAGE

    # Error when authentication fails.
    class AuthenticationFailedError < Error
      def initialize(credentials_type, github_message)
        @github_message = github_message
        message = "GitHub API Error: #{github_message}\n"
        message << case credentials_type
        when :github_cli_token
          <<~EOS
            Your GitHub CLI login session may be invalid.
            Refresh it with:
              gh auth login --hostname github.com
          EOS
        when :keychain_username_password
          <<~EOS
            The GitHub credentials in the macOS keychain may be invalid.
            Clear them with:
              printf "protocol=https\\nhost=github.com\\n" | git credential-osxkeychain erase
          EOS
        when :env_token
          require "utils/formatter"
          <<~EOS
            HOMEBREW_GITHUB_API_TOKEN may be invalid or expired; check:
              #{Formatter.url("https://github.com/settings/tokens")}
          EOS
        when :none
          NO_CREDENTIALS_MESSAGE
        end
        super message.freeze
      end
    end

    # Error when the user has no GitHub API credentials set at all (macOS keychain, GitHub CLI or envvar).
    class MissingAuthenticationError < Error
      def initialize
        super NO_CREDENTIALS_MESSAGE
      end
    end

    # Error when the API returns a validation error.
    class ValidationFailedError < Error
      def initialize(github_message, errors)
        @github_message = if errors.empty?
          github_message
        else
          "#{github_message}: #{errors}"
        end

        super(@github_message)
      end
    end

    ERRORS = [
      AuthenticationFailedError,
      HTTPNotFoundError,
      RateLimitExceededError,
      Error,
      JSON::ParserError,
    ].freeze

    # Gets the token from the GitHub CLI for github.com.
    sig { returns(T.nilable(String)) }
    def self.github_cli_token
      require "utils/uid"
      Utils::UID.drop_euid do
        # Avoid `Formula["gh"].opt_bin` so this method works even with `HOMEBREW_DISABLE_LOAD_FORMULA`.
        env = {
          "PATH" => PATH.new(HOMEBREW_PREFIX/"opt/gh/bin", ENV.fetch("PATH")),
          "HOME" => Utils::UID.uid_home,
        }.compact
        gh_out, _, result = system_command "gh",
                                           args:         ["auth", "token", "--hostname", "github.com"],
                                           env:,
                                           print_stderr: false
        return unless result.success?

        gh_out.chomp
      end
    end

    # Gets the password field from `git-credential-osxkeychain` for github.com,
    # but only if that password looks like a GitHub Personal Access Token.
    sig { returns(T.nilable(String)) }
    def self.keychain_username_password
      require "utils/uid"
      Utils::UID.drop_euid do
        git_credential_out, _, result = system_command "git",
                                                       args:         ["credential-osxkeychain", "get"],
                                                       input:        ["protocol=https\n", "host=github.com\n"],
                                                       env:          { "HOME" => Utils::UID.uid_home }.compact,
                                                       print_stderr: false
        return unless result.success?

        git_credential_out.force_encoding("ASCII-8BIT")
        github_username = git_credential_out[/^username=(.+)/, 1]
        github_password = git_credential_out[/^password=(.+)/, 1]
        return unless github_username

        # Don't use passwords from the keychain unless they look like
        # GitHub Personal Access Tokens:
        #   https://github.com/Homebrew/brew/issues/6862#issuecomment-572610344
        return unless GITHUB_PERSONAL_ACCESS_TOKEN_REGEX.match?(github_password)

        github_password
      end
    end

    def self.credentials
      @credentials ||= Homebrew::EnvConfig.github_api_token.presence
      @credentials ||= github_cli_token.presence
      @credentials ||= keychain_username_password.presence
    end

    sig { returns(Symbol) }
    def self.credentials_type
      if Homebrew::EnvConfig.github_api_token.present?
        :env_token
      elsif github_cli_token.present?
        :github_cli_token
      elsif keychain_username_password.present?
        :keychain_username_password
      else
        :none
      end
    end

    CREDENTIAL_NAMES = {
      env_token:                  "HOMEBREW_GITHUB_API_TOKEN",
      github_cli_token:           "GitHub CLI login",
      keychain_username_password: "macOS Keychain GitHub",
    }.freeze

    # Given an API response from GitHub, warn the user if their credentials
    # have insufficient permissions.
    def self.credentials_error_message(response_headers, needed_scopes)
      return if response_headers.empty?

      scopes = response_headers["x-accepted-oauth-scopes"].to_s.split(", ")
      needed_scopes = Set.new(scopes || needed_scopes)
      credentials_scopes = response_headers["x-oauth-scopes"]
      return if needed_scopes.subset?(Set.new(credentials_scopes.to_s.split(", ")))

      github_permission_link = GitHub.pat_blurb(needed_scopes.to_a)
      needed_scopes = needed_scopes.to_a.join(", ").presence || "none"
      credentials_scopes = "none" if credentials_scopes.blank?

      what = CREDENTIAL_NAMES.fetch(credentials_type)
      @credentials_error_message ||= onoe <<~EOS
        Your #{what} credentials do not have sufficient scope!
        Scopes required: #{needed_scopes}
        Scopes present:  #{credentials_scopes}
        #{github_permission_link}
      EOS
    end

    def self.open_rest(
      url, data: nil, data_binary_path: nil, request_method: nil, scopes: [].freeze, parse_json: true
    )
      # This is a no-op if the user is opting out of using the GitHub API.
      return block_given? ? yield({}) : {} if Homebrew::EnvConfig.no_github_api?

      # This is a Curl format token, not a Ruby one.
      # rubocop:disable Style/FormatStringToken
      args = ["--header", "Accept: application/vnd.github+json", "--write-out", "\n%{http_code}"]
      # rubocop:enable Style/FormatStringToken

      token = credentials
      args += ["--header", "Authorization: token #{token}"] if credentials_type != :none
      args += ["--header", "X-GitHub-Api-Version:2022-11-28"]

      require "tempfile"
      data_tmpfile = nil
      if data
        begin
          data = JSON.pretty_generate data
          data_tmpfile = Tempfile.new("github_api_post", HOMEBREW_TEMP)
        rescue JSON::ParserError => e
          raise Error, "Failed to parse JSON request:\n#{e.message}\n#{data}", e.backtrace
        end
      end

      if data_binary_path.present?
        args += ["--data-binary", "@#{data_binary_path}"]
        args += ["--header", "Content-Type: application/gzip"]
      end

      headers_tmpfile = Tempfile.new("github_api_headers", HOMEBREW_TEMP)
      begin
        if data_tmpfile
          data_tmpfile.write data
          data_tmpfile.close
          args += ["--data", "@#{data_tmpfile.path}"]

          args += ["--request", request_method.to_s] if request_method
        end

        args += ["--dump-header", T.must(headers_tmpfile.path)]

        require "utils/curl"
        result = Utils::Curl.curl_output("--location", url.to_s, *args, secrets: [token])
        output, _, http_code = result.stdout.rpartition("\n")
        output, _, http_code = output.rpartition("\n") if http_code == "000"
        headers = headers_tmpfile.read
      ensure
        if data_tmpfile
          data_tmpfile.close
          data_tmpfile.unlink
        end
        headers_tmpfile.close
        headers_tmpfile.unlink
      end

      begin
        if !http_code.start_with?("2") || !result.status.success?
          raise_error(output, result.stderr, http_code, headers, scopes)
        end

        return if http_code == "204" # No Content

        output = JSON.parse output if parse_json
        if block_given?
          yield output
        else
          output
        end
      rescue JSON::ParserError => e
        raise Error, "Failed to parse JSON response\n#{e.message}", e.backtrace
      end
    end

    def self.paginate_rest(url, additional_query_params: nil, per_page: 100, scopes: [].freeze)
      (1..API_MAX_PAGES).each do |page|
        retry_count = 1
        result = begin
          API.open_rest("#{url}?per_page=#{per_page}&page=#{page}&#{additional_query_params}", scopes:)
        rescue Error
          if retry_count < PAGINATE_RETRY_COUNT
            retry_count += 1
            retry
          end

          raise
        end
        break if result.blank?

        yield(result, page)
      end
    end

    def self.open_graphql(query, variables: nil, scopes: [].freeze, raise_errors: true)
      data = { query:, variables: }
      result = open_rest("#{API_URL}/graphql", scopes:, data:, request_method: "POST")

      if raise_errors
        raise Error, result["errors"].map { |e| e["message"] }.join("\n") if result["errors"].present?

        result["data"]
      else
        result
      end
    end

    sig {
      params(
        query:        String,
        variables:    T.nilable(T::Hash[Symbol, T.untyped]),
        scopes:       T::Array[String],
        raise_errors: T::Boolean,
        _block:       T.proc.params(data: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]),
      ).void
    }
    def self.paginate_graphql(query, variables: nil, scopes: [].freeze, raise_errors: true, &_block)
      result = API.open_graphql(query, variables:, scopes:, raise_errors:)

      has_next_page = T.let(true, T::Boolean)
      variables ||= {}
      while has_next_page
        page_info = yield result
        has_next_page = page_info["hasNextPage"]
        if has_next_page
          variables[:after] = page_info["endCursor"]
          result = API.open_graphql(query, variables:, scopes:, raise_errors:)
        end
      end
    end

    def self.raise_error(output, errors, http_code, headers, scopes)
      json = begin
        JSON.parse(output)
      rescue
        nil
      end
      message = json&.[]("message") || "curl failed! #{errors}"

      meta = {}
      headers.lines.each do |l|
        key, _, value = l.delete(":").partition(" ")
        key = key.downcase.strip
        next if key.empty?

        meta[key] = value.strip
      end

      credentials_error_message(meta, scopes)

      case http_code
      when "401"
        raise AuthenticationFailedError.new(credentials_type, message)
      when "403"
        if meta.fetch("x-ratelimit-remaining", 1).to_i <= 0
          reset = meta.fetch("x-ratelimit-reset").to_i
          raise RateLimitExceededError.new(reset, message)
        end

        raise AuthenticationFailedError.new(credentials_type, message)
      when "404"
        raise MissingAuthenticationError if credentials_type == :none && scopes.present?

        raise HTTPNotFoundError, message
      when "422"
        errors = json&.[]("errors") || []
        raise ValidationFailedError.new(message, errors)
      else
        raise Error, message
      end
    end
  end
end
