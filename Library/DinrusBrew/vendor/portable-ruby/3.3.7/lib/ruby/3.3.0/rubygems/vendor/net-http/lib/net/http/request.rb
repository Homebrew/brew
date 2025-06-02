# frozen_string_literal: true

# This class is the base class for \Gem::Net::HTTP request classes.
# The class should not be used directly;
# instead you should use its subclasses, listed below.
#
# == Creating a Request
#
# An request object may be created with either a Gem::URI or a string hostname:
#
#   require 'rubygems/vendor/net-http/lib/net/http'
#   uri = Gem::URI('https://jsonplaceholder.typicode.com/')
#   req = Gem::Net::HTTP::Get.new(uri)          # => #<Gem::Net::HTTP::Get GET>
#   req = Gem::Net::HTTP::Get.new(uri.hostname) # => #<Gem::Net::HTTP::Get GET>
#
# And with any of the subclasses:
#
#   req = Gem::Net::HTTP::Head.new(uri) # => #<Gem::Net::HTTP::Head HEAD>
#   req = Gem::Net::HTTP::Post.new(uri) # => #<Gem::Net::HTTP::Post POST>
#   req = Gem::Net::HTTP::Put.new(uri)  # => #<Gem::Net::HTTP::Put PUT>
#   # ...
#
# The new instance is suitable for use as the argument to Gem::Net::HTTP#request.
#
# == Request Headers
#
# A new request object has these header fields by default:
#
#   req.to_hash
#   # =>
#   {"accept-encoding"=>["gzip;q=1.0,deflate;q=0.6,identity;q=0.3"],
#   "accept"=>["*/*"],
#   "user-agent"=>["Ruby"],
#   "host"=>["jsonplaceholder.typicode.com"]}
#
# See:
#
# - {Request header Accept-Encoding}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#Accept-Encoding]
#   and {Compression and Decompression}[rdoc-ref:Gem::Net::HTTP@Compression+and+Decompression].
# - {Request header Accept}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#accept-request-header].
# - {Request header User-Agent}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#user-agent-request-header].
# - {Request header Host}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#host-request-header].
#
# You can add headers or override default headers:
#
#   #   res = Gem::Net::HTTP::Get.new(uri, {'foo' => '0', 'bar' => '1'})
#
# This class (and therefore its subclasses) also includes (indirectly)
# module Gem::Net::HTTPHeader, which gives access to its
# {methods for setting headers}[rdoc-ref:Gem::Net::HTTPHeader@Setters].
#
# == Request Subclasses
#
# Subclasses for HTTP requests:
#
# - Gem::Net::HTTP::Get
# - Gem::Net::HTTP::Head
# - Gem::Net::HTTP::Post
# - Gem::Net::HTTP::Put
# - Gem::Net::HTTP::Delete
# - Gem::Net::HTTP::Options
# - Gem::Net::HTTP::Trace
# - Gem::Net::HTTP::Patch
#
# Subclasses for WebDAV requests:
#
# - Gem::Net::HTTP::Propfind
# - Gem::Net::HTTP::Proppatch
# - Gem::Net::HTTP::Mkcol
# - Gem::Net::HTTP::Copy
# - Gem::Net::HTTP::Move
# - Gem::Net::HTTP::Lock
# - Gem::Net::HTTP::Unlock
#
class Gem::Net::HTTPRequest < Gem::Net::HTTPGenericRequest
  # Creates an HTTP request object for +path+.
  #
  # +initheader+ are the default headers to use.  Gem::Net::HTTP adds
  # Accept-Encoding to enable compression of the response body unless
  # Accept-Encoding or Range are supplied in +initheader+.

  def initialize(path, initheader = nil)
    super self.class::METHOD,
          self.class::REQUEST_HAS_BODY,
          self.class::RESPONSE_HAS_BODY,
          path, initheader
  end
end
