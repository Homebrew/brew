# frozen_string_literal: true

class Gem::Request::ConnectionPools # :nodoc:
  @client = Net::HTTP

  class << self
    attr_accessor :client
  end

  def initialize(proxy_uri, cert_files)
    @proxy_uri  = proxy_uri
    @cert_files = cert_files
    @pools      = {}
    @pool_mutex = Thread::Mutex.new
  end

  def pool_for(uri)
    http_args = net_http_args(uri, @proxy_uri)
    key       = http_args + [https?(uri)]
    @pool_mutex.synchronize do
      @pools[key] ||=
        if https? uri
          Gem::Request::HTTPSPool.new(http_args, @cert_files, @proxy_uri)
        else
          Gem::Request::HTTPPool.new(http_args, @cert_files, @proxy_uri)
        end
    end
  end

  def close_all
    @pools.each_value {|pool| pool.close_all }
  end

  private

  ##
  # Returns list of no_proxy entries (if any) from the environment

  def get_no_proxy_from_env
    env_no_proxy = ENV["no_proxy"] || ENV["NO_PROXY"]

    return [] if env_no_proxy.nil? || env_no_proxy.empty?

    env_no_proxy.split(/\s*,\s*/)
  end

  def https?(uri)
    uri.scheme.downcase == "https"
  end

  def no_proxy?(host, env_no_proxy)
    host = host.downcase

    env_no_proxy.any? do |pattern|
      env_no_proxy_pattern = pattern.downcase.dup

      # Remove dot in front of pattern for wildcard matching
      env_no_proxy_pattern[0] = "" if env_no_proxy_pattern[0] == "."

      host_tokens = host.split(".")
      pattern_tokens = env_no_proxy_pattern.split(".")

      intersection = (host_tokens - pattern_tokens) | (pattern_tokens - host_tokens)

      # When we do the split into tokens we miss a dot character, so add it back if we need it
      missing_dot = intersection.length > 0 ? 1 : 0
      start = intersection.join(".").size + missing_dot

      no_proxy_host = host[start..-1]

      env_no_proxy_pattern == no_proxy_host
    end
  end

  def net_http_args(uri, proxy_uri)
    hostname = uri.hostname
    net_http_args = [hostname, uri.port]

    no_proxy = get_no_proxy_from_env

    if proxy_uri && !no_proxy?(hostname, no_proxy)
      proxy_hostname = proxy_uri.respond_to?(:hostname) ? proxy_uri.hostname : proxy_uri.host
      net_http_args + [
        proxy_hostname,
        proxy_uri.port,
        Gem::UriFormatter.new(proxy_uri.user).unescape,
        Gem::UriFormatter.new(proxy_uri.password).unescape,
      ]
    elsif no_proxy? hostname, no_proxy
      net_http_args + [nil, nil]
    else
      net_http_args
    end
  end
end
