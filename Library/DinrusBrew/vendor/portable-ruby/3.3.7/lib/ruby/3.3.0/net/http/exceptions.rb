# frozen_string_literal: true
module Net
  # Net::HTTP exception class.
  # You cannot use Net::HTTPExceptions directly; instead, you must use
  # its subclasses.
  module HTTPExceptions
    def initialize(msg, res)   #:nodoc:
      super msg
      @response = res
    end
    attr_reader :response
    alias data response    #:nodoc: obsolete
  end

  class HTTPError < ProtocolError
    include HTTPExceptions
  end

  class HTTPRetriableError < ProtoRetriableError
    include HTTPExceptions
  end

  class HTTPClientException < ProtoServerError
    include HTTPExceptions
  end

  class HTTPFatalError < ProtoFatalError
    include HTTPExceptions
  end

  # We cannot use the name "HTTPServerError", it is the name of the response.
  HTTPServerException = HTTPClientException # :nodoc:
  deprecate_constant(:HTTPServerException)
end
