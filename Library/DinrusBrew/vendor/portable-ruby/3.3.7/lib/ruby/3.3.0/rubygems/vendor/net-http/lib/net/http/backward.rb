# frozen_string_literal: true
# for backward compatibility

# :enddoc:

class Gem::Net::HTTP
  ProxyMod = ProxyDelta
  deprecate_constant :ProxyMod
end

module Gem::Net::NetPrivate
  HTTPRequest = ::Gem::Net::HTTPRequest
  deprecate_constant :HTTPRequest
end

module Gem::Net
  HTTPSession = HTTP

  HTTPInformationCode  = HTTPInformation
  HTTPSuccessCode      = HTTPSuccess
  HTTPRedirectionCode  = HTTPRedirection
  HTTPRetriableCode    = HTTPRedirection
  HTTPClientErrorCode  = HTTPClientError
  HTTPFatalErrorCode   = HTTPClientError
  HTTPServerErrorCode  = HTTPServerError
  HTTPResponseReceiver = HTTPResponse

  HTTPResponceReceiver = HTTPResponse # Typo since 2001

  deprecate_constant :HTTPSession,
                     :HTTPInformationCode,
                     :HTTPSuccessCode,
                     :HTTPRedirectionCode,
                     :HTTPRetriableCode,
                     :HTTPClientErrorCode,
                     :HTTPFatalErrorCode,
                     :HTTPServerErrorCode,
                     :HTTPResponseReceiver,
                     :HTTPResponceReceiver
end
