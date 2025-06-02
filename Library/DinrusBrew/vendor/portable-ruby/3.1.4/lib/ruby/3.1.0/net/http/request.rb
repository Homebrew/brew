# frozen_string_literal: false
# HTTP request class.
# This class wraps together the request header and the request path.
# You cannot use this class directly. Instead, you should use one of its
# subclasses: Net::HTTP::Get, Net::HTTP::Post, Net::HTTP::Head.
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

