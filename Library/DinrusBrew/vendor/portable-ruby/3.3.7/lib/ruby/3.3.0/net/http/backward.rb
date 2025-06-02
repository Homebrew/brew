# frozen_string_literal: true
# for backward compatibility

# :enddoc:

class Net::HTTP
  ProxyMod = ProxyDelta
  deprecate_constant :ProxyMod
end

module Net::NetPrivate
  HTTPRequest = ::Net::HTTPRequest
  deprecate_constant :HTTPRequest
end

module Net
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
