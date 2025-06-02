# frozen_string_literal: true
#--
# https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml

module Net
  # :stopdoc:

  class HTTPUnknownResponse < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end
  class HTTPInformation < HTTPResponse          # 1xx
    HAS_BODY = false
    EXCEPTION_TYPE = HTTPError                  #
  end
  class HTTPSuccess < HTTPResponse              # 2xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end
  class HTTPRedirection < HTTPResponse          # 3xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPRetriableError         #
  end
  class HTTPClientError < HTTPResponse          # 4xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPClientException        #
  end
  class HTTPServerError < HTTPResponse          # 5xx
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPFatalError             #
  end

  class HTTPContinue < HTTPInformation          # 100
    HAS_BODY = false
  end
  class HTTPSwitchProtocol < HTTPInformation    # 101
    HAS_BODY = false
  end
  class HTTPProcessing < HTTPInformation        # 102
    HAS_BODY = false
  end
  class HTTPEarlyHints < HTTPInformation        # 103 - RFC 8297
    HAS_BODY = false
  end

  class HTTPOK < HTTPSuccess                            # 200
    HAS_BODY = true
  end
  class HTTPCreated < HTTPSuccess                       # 201
    HAS_BODY = true
  end
  class HTTPAccepted < HTTPSuccess                      # 202
    HAS_BODY = true
  end
  class HTTPNonAuthoritativeInformation < HTTPSuccess   # 203
    HAS_BODY = true
  end
  class HTTPNoContent < HTTPSuccess                     # 204
    HAS_BODY = false
  end
  class HTTPResetContent < HTTPSuccess                  # 205
    HAS_BODY = false
  end
  class HTTPPartialContent < HTTPSuccess                # 206
    HAS_BODY = true
  end
  class HTTPMultiStatus < HTTPSuccess                   # 207 - RFC 4918
    HAS_BODY = true
  end
  class HTTPAlreadyReported < HTTPSuccess               # 208 - RFC 5842
    HAS_BODY = true
  end
  class HTTPIMUsed < HTTPSuccess                        # 226 - RFC 3229
    HAS_BODY = true
  end

  class HTTPMultipleChoices < HTTPRedirection   # 300
    HAS_BODY = true
  end
  HTTPMultipleChoice = HTTPMultipleChoices
  class HTTPMovedPermanently < HTTPRedirection  # 301
    HAS_BODY = true
  end
  class HTTPFound < HTTPRedirection             # 302
    HAS_BODY = true
  end
  HTTPMovedTemporarily = HTTPFound
  class HTTPSeeOther < HTTPRedirection          # 303
    HAS_BODY = true
  end
  class HTTPNotModified < HTTPRedirection       # 304
    HAS_BODY = false
  end
  class HTTPUseProxy < HTTPRedirection          # 305
    HAS_BODY = false
  end
  # 306 Switch Proxy - no longer unused
  class HTTPTemporaryRedirect < HTTPRedirection # 307
    HAS_BODY = true
  end
  class HTTPPermanentRedirect < HTTPRedirection # 308
    HAS_BODY = true
  end

  class HTTPBadRequest < HTTPClientError                    # 400
    HAS_BODY = true
  end
  class HTTPUnauthorized < HTTPClientError                  # 401
    HAS_BODY = true
  end
  class HTTPPaymentRequired < HTTPClientError               # 402
    HAS_BODY = true
  end
  class HTTPForbidden < HTTPClientError                     # 403
    HAS_BODY = true
  end
  class HTTPNotFound < HTTPClientError                      # 404
    HAS_BODY = true
  end
  class HTTPMethodNotAllowed < HTTPClientError              # 405
    HAS_BODY = true
  end
  class HTTPNotAcceptable < HTTPClientError                 # 406
    HAS_BODY = true
  end
  class HTTPProxyAuthenticationRequired < HTTPClientError   # 407
    HAS_BODY = true
  end
  class HTTPRequestTimeout < HTTPClientError                # 408
    HAS_BODY = true
  end
  HTTPRequestTimeOut = HTTPRequestTimeout
  class HTTPConflict < HTTPClientError                      # 409
    HAS_BODY = true
  end
  class HTTPGone < HTTPClientError                          # 410
    HAS_BODY = true
  end
  class HTTPLengthRequired < HTTPClientError                # 411
    HAS_BODY = true
  end
  class HTTPPreconditionFailed < HTTPClientError            # 412
    HAS_BODY = true
  end
  class HTTPPayloadTooLarge < HTTPClientError               # 413
    HAS_BODY = true
  end
  HTTPRequestEntityTooLarge = HTTPPayloadTooLarge
  class HTTPURITooLong < HTTPClientError                    # 414
    HAS_BODY = true
  end
  HTTPRequestURITooLong = HTTPURITooLong
  HTTPRequestURITooLarge = HTTPRequestURITooLong
  class HTTPUnsupportedMediaType < HTTPClientError          # 415
    HAS_BODY = true
  end
  class HTTPRangeNotSatisfiable < HTTPClientError           # 416
    HAS_BODY = true
  end
  HTTPRequestedRangeNotSatisfiable = HTTPRangeNotSatisfiable
  class HTTPExpectationFailed < HTTPClientError             # 417
    HAS_BODY = true
  end
  # 418 I'm a teapot - RFC 2324; a joke RFC
  # 420 Enhance Your Calm - Twitter
  class HTTPMisdirectedRequest < HTTPClientError            # 421 - RFC 7540
    HAS_BODY = true
  end
  class HTTPUnprocessableEntity < HTTPClientError           # 422 - RFC 4918
    HAS_BODY = true
  end
  class HTTPLocked < HTTPClientError                        # 423 - RFC 4918
    HAS_BODY = true
  end
  class HTTPFailedDependency < HTTPClientError              # 424 - RFC 4918
    HAS_BODY = true
  end
  # 425 Unordered Collection - existed only in draft
  class HTTPUpgradeRequired < HTTPClientError               # 426 - RFC 2817
    HAS_BODY = true
  end
  class HTTPPreconditionRequired < HTTPClientError          # 428 - RFC 6585
    HAS_BODY = true
  end
  class HTTPTooManyRequests < HTTPClientError               # 429 - RFC 6585
    HAS_BODY = true
  end
  class HTTPRequestHeaderFieldsTooLarge < HTTPClientError   # 431 - RFC 6585
    HAS_BODY = true
  end
  class HTTPUnavailableForLegalReasons < HTTPClientError    # 451 - RFC 7725
    HAS_BODY = true
  end
  # 444 No Response - Nginx
  # 449 Retry With - Microsoft
  # 450 Blocked by Windows Parental Controls - Microsoft
  # 499 Client Closed Request - Nginx

  class HTTPInternalServerError < HTTPServerError           # 500
    HAS_BODY = true
  end
  class HTTPNotImplemented < HTTPServerError                # 501
    HAS_BODY = true
  end
  class HTTPBadGateway < HTTPServerError                    # 502
    HAS_BODY = true
  end
  class HTTPServiceUnavailable < HTTPServerError            # 503
    HAS_BODY = true
  end
  class HTTPGatewayTimeout < HTTPServerError                # 504
    HAS_BODY = true
  end
  HTTPGatewayTimeOut = HTTPGatewayTimeout
  class HTTPVersionNotSupported < HTTPServerError           # 505
    HAS_BODY = true
  end
  class HTTPVariantAlsoNegotiates < HTTPServerError         # 506
    HAS_BODY = true
  end
  class HTTPInsufficientStorage < HTTPServerError           # 507 - RFC 4918
    HAS_BODY = true
  end
  class HTTPLoopDetected < HTTPServerError                  # 508 - RFC 5842
    HAS_BODY = true
  end
  # 509 Bandwidth Limit Exceeded - Apache bw/limited extension
  class HTTPNotExtended < HTTPServerError                   # 510 - RFC 2774
    HAS_BODY = true
  end
  class HTTPNetworkAuthenticationRequired < HTTPServerError # 511 - RFC 6585
    HAS_BODY = true
  end

  # :startdoc:
end

class Net::HTTPResponse
  CODE_CLASS_TO_OBJ = {
    '1' => Net::HTTPInformation,
    '2' => Net::HTTPSuccess,
    '3' => Net::HTTPRedirection,
    '4' => Net::HTTPClientError,
    '5' => Net::HTTPServerError
  }
  CODE_TO_OBJ = {
    '100' => Net::HTTPContinue,
    '101' => Net::HTTPSwitchProtocol,
    '102' => Net::HTTPProcessing,
    '103' => Net::HTTPEarlyHints,

    '200' => Net::HTTPOK,
    '201' => Net::HTTPCreated,
    '202' => Net::HTTPAccepted,
    '203' => Net::HTTPNonAuthoritativeInformation,
    '204' => Net::HTTPNoContent,
    '205' => Net::HTTPResetContent,
    '206' => Net::HTTPPartialContent,
    '207' => Net::HTTPMultiStatus,
    '208' => Net::HTTPAlreadyReported,
    '226' => Net::HTTPIMUsed,

    '300' => Net::HTTPMultipleChoices,
    '301' => Net::HTTPMovedPermanently,
    '302' => Net::HTTPFound,
    '303' => Net::HTTPSeeOther,
    '304' => Net::HTTPNotModified,
    '305' => Net::HTTPUseProxy,
    '307' => Net::HTTPTemporaryRedirect,
    '308' => Net::HTTPPermanentRedirect,

    '400' => Net::HTTPBadRequest,
    '401' => Net::HTTPUnauthorized,
    '402' => Net::HTTPPaymentRequired,
    '403' => Net::HTTPForbidden,
    '404' => Net::HTTPNotFound,
    '405' => Net::HTTPMethodNotAllowed,
    '406' => Net::HTTPNotAcceptable,
    '407' => Net::HTTPProxyAuthenticationRequired,
    '408' => Net::HTTPRequestTimeout,
    '409' => Net::HTTPConflict,
    '410' => Net::HTTPGone,
    '411' => Net::HTTPLengthRequired,
    '412' => Net::HTTPPreconditionFailed,
    '413' => Net::HTTPPayloadTooLarge,
    '414' => Net::HTTPURITooLong,
    '415' => Net::HTTPUnsupportedMediaType,
    '416' => Net::HTTPRangeNotSatisfiable,
    '417' => Net::HTTPExpectationFailed,
    '421' => Net::HTTPMisdirectedRequest,
    '422' => Net::HTTPUnprocessableEntity,
    '423' => Net::HTTPLocked,
    '424' => Net::HTTPFailedDependency,
    '426' => Net::HTTPUpgradeRequired,
    '428' => Net::HTTPPreconditionRequired,
    '429' => Net::HTTPTooManyRequests,
    '431' => Net::HTTPRequestHeaderFieldsTooLarge,
    '451' => Net::HTTPUnavailableForLegalReasons,

    '500' => Net::HTTPInternalServerError,
    '501' => Net::HTTPNotImplemented,
    '502' => Net::HTTPBadGateway,
    '503' => Net::HTTPServiceUnavailable,
    '504' => Net::HTTPGatewayTimeout,
    '505' => Net::HTTPVersionNotSupported,
    '506' => Net::HTTPVariantAlsoNegotiates,
    '507' => Net::HTTPInsufficientStorage,
    '508' => Net::HTTPLoopDetected,
    '510' => Net::HTTPNotExtended,
    '511' => Net::HTTPNetworkAuthenticationRequired,
  }
end
