# frozen_string_literal: true

module Bundler
  module Persistent
    module Net
      module HTTP
      end
    end
  end
end
require_relative "vendor/net-http-persistent/lib/net/http/persistent"

module Bundler
  class PersistentHTTP < Persistent::Net::HTTP::Persistent
    def connection_for(uri)
      super(uri) do |connection|
        result = yield connection
        warn_old_tls_version_rubygems_connection(uri, connection)
        result
      end
    end

    def warn_old_tls_version_rubygems_connection(uri, connection)
      return unless connection.http.use_ssl?
      return unless (uri.host || "").end_with?("rubygems.org")

      socket = connection.instance_variable_get(:@socket)
      return unless socket
      socket_io = socket.io
      return unless socket_io.respond_to?(:ssl_version)
      ssl_version = socket_io.ssl_version

      case ssl_version
      when /TLSv([\d\.]+)/
        version = Gem::Version.new($1)
        if version < Gem::Version.new("1.2")
          Bundler.ui.warn \
            "Warning: Your Ruby version is compiled against a copy of OpenSSL that is very old. " \
            "Starting in January 2018, RubyGems.org will refuse connection requests from these " \
            "very old versions of OpenSSL. If you will need to continue installing gems after " \
            "January 2018, please follow this guide to upgrade: http://ruby.to/tls-outdated.",
            :wrap => true
        end
      end
    end
  end
end
