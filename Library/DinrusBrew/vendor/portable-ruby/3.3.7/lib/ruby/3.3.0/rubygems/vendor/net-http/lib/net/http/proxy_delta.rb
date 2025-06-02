# frozen_string_literal: true
module Gem::Net::HTTP::ProxyDelta   #:nodoc: internal use only
  private

  def conn_address
    proxy_address()
  end

  def conn_port
    proxy_port()
  end

  def edit_path(path)
    use_ssl? ? path : "http://#{addr_port()}#{path}"
  end
end

