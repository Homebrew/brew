# frozen_string_literal: true

# This class is the base class for \Net::HTTP request classes.
# The class should not be used directly;
# instead you should use its subclasses, listed below.
#
# == Creating a Request
#
# An request object may be created with either a URI or a string hostname:
#
#   require 'net/http'
#   uri = URI('https://jsonplaceholder.typicode.com/')
#   req = Net::HTTP::Get.new(uri)          # => #<Net::HTTP::Get GET>
#   req = Net::HTTP::Get.new(uri.hostname) # => #<Net::HTTP::Get GET>
#
# And with any of the subclasses:
#
#   req = Net::HTTP::Head.new(uri) # => #<Net::HTTP::Head HEAD>
#   req = Net::HTTP::Post.new(uri) # => #<Net::HTTP::Post POST>
#   req = Net::HTTP::Put.new(uri)  # => #<Net::HTTP::Put PUT>
#   # ...
#
# The new instance is suitable for use as the argument to Net::HTTP#request.
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
#   and {Compression and Decompression}[rdoc-ref:Net::HTTP@Compression+and+Decompression].
# - {Request header Accept}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#accept-request-header].
# - {Request header User-Agent}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#user-agent-request-header].
# - {Request header Host}[https://en.wikipedia.org/wiki/List_of_HTTP_header_fields#host-request-header].
#
# You can add headers or override default headers:
#
#   #   res = Net::HTTP::Get.new(uri, {'foo' => '0', 'bar' => '1'})
#
# This class (and therefore its subclasses) also includes (indirectly)
# module Net::HTTPHeader, which gives access to its
# {methods for setting headers}[rdoc-ref:Net::HTTPHeader@Setters].
#
# == Request Subclasses
#
# Subclasses for HTTP requests:
#
# - Net::HTTP::Get
# - Net::HTTP::Head
# - Net::HTTP::Post
# - Net::HTTP::Put
# - Net::HTTP::Delete
# - Net::HTTP::Options
# - Net::HTTP::Trace
# - Net::HTTP::Patch
#
# Subclasses for WebDAV requests:
#
# - Net::HTTP::Propfind
# - Net::HTTP::Proppatch
# - Net::HTTP::Mkcol
# - Net::HTTP::Copy
# - Net::HTTP::Move
# - Net::HTTP::Lock
# - Net::HTTP::Unlock
#
class Net::HTTPRequest < Net::HTTPGenericRequest
  # Creates an HTTP request object for +path+.
  #
  # +initheader+ are the default headers to use.  Net::HTTP adds
  # Accept-Encoding to enable compression of the response body unless
  # Accept-Encoding or Range are supplied in +initheader+.

  def initialize(path, initheader = nil)
    super self.class::METHOD,
          self.class::REQUEST_HAS_BODY,
          self.class::RESPONSE_HAS_BODY,
          path, initheader
  end
end
