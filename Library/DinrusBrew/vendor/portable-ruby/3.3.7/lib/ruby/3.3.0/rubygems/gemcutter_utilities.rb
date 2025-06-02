# frozen_string_literal: true

require_relative "remote_fetcher"
require_relative "text"
require_relative "gemcutter_utilities/webauthn_listener"
require_relative "gemcutter_utilities/webauthn_poller"

##
# Utility methods for using the RubyGems API.

module Gem::GemcutterUtilities
  ERROR_CODE = 1
  API_SCOPES = [:index_rubygems, :push_rubygem, :yank_rubygem, :add_owner, :remove_owner, :access_webhooks].freeze
  EXCLUSIVELY_API_SCOPES = [:show_dashboard].freeze

  include Gem::Text

  attr_writer :host
  attr_writer :scope

  ##
  # Add the --key option

  def add_key_option
    add_option("-k", "--key KEYNAME", Symbol,
               "Use the given API key",
               "from #{Gem.configuration.credentials_path}") do |value,options|
      options[:key] = value
    end
  end

  ##
  # Add the --otp option

  def add_otp_option
    add_option("--otp CODE",
               "Digit code for multifactor authentication",
               "You can also use the environment variable GEM_HOST_OTP_CODE") do |value, options|
      options[:otp] = value
    end
  end

  ##
  # The API key from the command options or from the user's configuration.

  def api_key
    if ENV["GEM_HOST_API_KEY"]
      ENV["GEM_HOST_API_KEY"]
    elsif options[:key]
      verify_api_key options[:key]
    elsif Gem.configuration.api_keys.key?(host)
      Gem.configuration.api_keys[host]
    else
      Gem.configuration.rubygems_api_key
    end
  end

  ##
  # The OTP code from the command options or from the user's configuration.

  def otp
    options[:otp] || ENV["GEM_HOST_OTP_CODE"]
  end

  ##
  # The host to connect to either from the RUBYGEMS_HOST environment variable
  # or from the user's configuration

  def host
    configured_host = Gem.host unless
      Gem.configuration.disable_default_gem_server

    @host ||=
      begin
        env_rubygems_host = ENV["RUBYGEMS_HOST"]
        env_rubygems_host = nil if env_rubygems_host&.empty?

        env_rubygems_host || configured_host
      end
  end

  ##
  # Creates an RubyGems API to +host+ and +path+ with the given HTTP +method+.
  #
  # If +allowed_push_host+ metadata is present, then it will only allow that host.

  def rubygems_api_request(method, path, host = nil, allowed_push_host = nil, scope: nil, credentials: {}, &block)
    require_relative "vendored_net_http"

    self.host = host if host
    unless self.host
      alert_error "You must specify a gem server"
      terminate_interaction(ERROR_CODE)
    end

    if allowed_push_host
      allowed_host_uri = Gem::URI.parse(allowed_push_host)
      host_uri         = Gem::URI.parse(self.host)

      unless (host_uri.scheme == allowed_host_uri.scheme) && (host_uri.host == allowed_host_uri.host)
        alert_error "#{self.host.inspect} is not allowed by the gemspec, which only allows #{allowed_push_host.inspect}"
        terminate_interaction(ERROR_CODE)
      end
    end

    uri = Gem::URI.parse "#{self.host}/#{path}"
    response = request_with_otp(method, uri, &block)

    if mfa_unauthorized?(response)
      fetch_otp(credentials)
      response = request_with_otp(method, uri, &block)
    end

    if api_key_forbidden?(response)
      update_scope(scope)
      request_with_otp(method, uri, &block)
    else
      response
    end
  end

  def mfa_unauthorized?(response)
    response.is_a?(Gem::Net::HTTPUnauthorized) && response.body.start_with?("You have enabled multifactor authentication")
  end

  def update_scope(scope)
    sign_in_host        = host
    pretty_host         = pretty_host(sign_in_host)
    update_scope_params = { scope => true }

    say "The existing key doesn't have access of #{scope} on #{pretty_host}. Please sign in to update access."

    identifier = ask "Username/email: "
    password   = ask_for_password "      Password: "

    response = rubygems_api_request(:put, "api/v1/api_key",
                                    sign_in_host, scope: scope) do |request|
      request.basic_auth identifier, password
      request["OTP"] = otp if otp
      request.body = Gem::URI.encode_www_form({ api_key: api_key }.merge(update_scope_params))
    end

    with_response response do |_resp|
      say "Added #{scope} scope to the existing API key"
    end
  end

  ##
  # Signs in with the RubyGems API at +sign_in_host+ and sets the rubygems API
  # key.

  def sign_in(sign_in_host = nil, scope: nil)
    sign_in_host ||= host
    return if api_key

    pretty_host = pretty_host(sign_in_host)

    say "Enter your #{pretty_host} credentials."
    say "Don't have an account yet? " \
        "Create one at #{sign_in_host}/sign_up"

    identifier = ask "Username/email: "
    password   = ask_for_password "      Password: "
    say "\n"

    key_name     = get_key_name(scope)
    scope_params = get_scope_params(scope)
    profile      = get_user_profile(identifier, password)
    mfa_params   = get_mfa_params(profile)
    all_params   = scope_params.merge(mfa_params)
    warning      = profile["warning"]
    credentials  = { identifier: identifier, password: password }

    say "#{warning}\n" if warning

    response = rubygems_api_request(:post, "api/v1/api_key",
                                    sign_in_host, credentials: credentials, scope: scope) do |request|
      request.basic_auth identifier, password
      request["OTP"] = otp if otp
      request.body = Gem::URI.encode_www_form({ name: key_name }.merge(all_params))
    end

    with_response response do |resp|
      say "Signed in with API key: #{key_name}."
      set_api_key host, resp.body
    end
  end

  ##
  # Retrieves the pre-configured API key +key+ or terminates interaction with
  # an error.

  def verify_api_key(key)
    if Gem.configuration.api_keys.key? key
      Gem.configuration.api_keys[key]
    else
      alert_error "No such API key. Please add it to your configuration (done automatically on initial `gem push`)."
      terminate_interaction(ERROR_CODE)
    end
  end

  ##
  # If +response+ is an HTTP Success (2XX) response, yields the response if a
  # block was given or shows the response body to the user.
  #
  # If the response was not successful, shows an error to the user including
  # the +error_prefix+ and the response body. If the response was a permanent redirect,
  # shows an error to the user including the redirect location.

  def with_response(response, error_prefix = nil)
    case response
    when Gem::Net::HTTPSuccess then
      if block_given?
        yield response
      else
        say clean_text(response.body)
      end
    when Gem::Net::HTTPPermanentRedirect, Gem::Net::HTTPRedirection then
      message = "The request has redirected permanently to #{response["location"]}. Please check your defined push host URL."
      message = "#{error_prefix}: #{message}" if error_prefix

      say clean_text(message)
      terminate_interaction(ERROR_CODE)
    else
      message = response.body
      message = "#{error_prefix}: #{message}" if error_prefix

      say clean_text(message)
      terminate_interaction(ERROR_CODE)
    end
  end

  ##
  # Returns true when the user has enabled multifactor authentication from
  # +response+ text and no otp provided by options.

  def set_api_key(host, key)
    if default_host?
      Gem.configuration.rubygems_api_key = key
    else
      Gem.configuration.set_api_key host, key
    end
  end

  private

  def request_with_otp(method, uri, &block)
    request_method = Gem::Net::HTTP.const_get method.to_s.capitalize

    Gem::RemoteFetcher.fetcher.request(uri, request_method) do |req|
      req["OTP"] = otp if otp
      block.call(req)
    end
  end

  def fetch_otp(credentials)
    options[:otp] = if webauthn_url = webauthn_verification_url(credentials)
      server = TCPServer.new 0
      port = server.addr[1].to_s

      url_with_port = "#{webauthn_url}?port=#{port}"
      say "You have enabled multi-factor authentication. Please visit #{url_with_port} to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, you can re-run the gem signin command with the `--otp [your_code]` option."

      threads = [WebauthnListener.listener_thread(host, server), WebauthnPoller.poll_thread(options, host, webauthn_url, credentials)]
      otp_thread = wait_for_otp_thread(*threads)

      threads.each(&:join)

      if error = otp_thread[:error]
        alert_error error.message
        terminate_interaction(1)
      end

      say "You are verified with a security device. You may close the browser window."
      otp_thread[:otp]
    else
      say "You have enabled multi-factor authentication. Please enter OTP code."
      ask "Code: "
    end
  end

  def wait_for_otp_thread(*threads)
    loop do
      threads.each do |otp_thread|
        return otp_thread unless otp_thread.alive?
      end
      sleep 0.1
    end
  ensure
    threads.each(&:exit)
  end

  def webauthn_verification_url(credentials)
    response = rubygems_api_request(:post, "api/v1/webauthn_verification") do |request|
      if credentials.empty?
        request.add_field "Authorization", api_key
      else
        request.basic_auth credentials[:identifier], credentials[:password]
      end
    end
    response.is_a?(Gem::Net::HTTPSuccess) ? response.body : nil
  end

  def pretty_host(host)
    if default_host?
      "RubyGems.org"
    else
      host
    end
  end

  def get_scope_params(scope)
    scope_params = { index_rubygems: true }

    if scope
      scope_params = { scope => true }
    else
      say "The default access scope is:"
      scope_params.each do |k, _v|
        say "  #{k}: y"
      end
      say "\n"
      customise = ask_yes_no("Do you want to customise scopes?", false)
      if customise
        EXCLUSIVELY_API_SCOPES.each do |excl_scope|
          selected = ask_yes_no("#{excl_scope} (exclusive scope, answering yes will not prompt for other scopes)", false)
          next unless selected

          return { excl_scope => true }
        end

        scope_params = {}

        API_SCOPES.each do |s|
          selected = ask_yes_no(s.to_s, false)
          scope_params[s] = true if selected
        end
      end
      say "\n"
    end

    scope_params
  end

  def default_host?
    host == Gem::DEFAULT_HOST
  end

  def get_user_profile(identifier, password)
    return {} unless default_host?

    response = rubygems_api_request(:get, "api/v1/profile/me.yaml") do |request|
      request.basic_auth identifier, password
    end

    with_response response do |resp|
      Gem::ConfigFile.load_with_rubygems_config_hash(clean_text(resp.body))
    end
  end

  def get_mfa_params(profile)
    mfa_level = profile["mfa"]
    params = {}
    if ["ui_only", "ui_and_gem_signin"].include?(mfa_level)
      selected = ask_yes_no("Would you like to enable MFA for this key? (strongly recommended)")
      params["mfa"] = true if selected
    end
    params
  end

  def get_key_name(scope)
    hostname = Socket.gethostname || "unknown-host"
    user = ENV["USER"] || ENV["USERNAME"] || "unknown-user"
    ts = Time.now.strftime("%Y%m%d%H%M%S")
    default_key_name = "#{hostname}-#{user}-#{ts}"

    key_name = ask "API Key name [#{default_key_name}]: " unless scope
    if key_name.nil? || key_name.empty?
      default_key_name
    else
      key_name
    end
  end

  def api_key_forbidden?(response)
    response.is_a?(Gem::Net::HTTPForbidden) && response.body.start_with?("The API key doesn't have access")
  end
end
