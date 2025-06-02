# frozen_string_literal: true
#--
# https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml

module Gem::Net

  class HTTPUnknownResponse < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for informational (1xx) HTTP response classes.
  #
  # An informational response indicates that the request was received and understood.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.1xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#1xx_informational_response].
  #
  class HTTPInformation < HTTPResponse
    HAS_BODY = false
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for success (2xx) HTTP response classes.
  #
  # A success response indicates the action requested by the client
  # was received, understood, and accepted.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.2xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#2xx_success].
  #
  class HTTPSuccess < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for redirection (3xx) HTTP response classes.
  #
  # A redirection response indicates the client must take additional action
  # to complete the request.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.3xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#3xx_redirection].
  #
  class HTTPRedirection < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPRetriableError         #
  end

  # Parent class for client error (4xx) HTTP response classes.
  #
  # A client error response indicates that the client may have caused an error.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.4xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#4xx_client_errors].
  #
  class HTTPClientError < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPClientException        #
  end

  # Parent class for server error (5xx) HTTP response classes.
  #
  # A server error response indicates that the server failed to fulfill a request.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.5xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#5xx_server_errors].
  #
  class HTTPServerError < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPFatalError             #
  end

  # Response class for +Continue+ responses (status code 100).
  #
  # A +Continue+ response indicates that the server has received the request headers.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/100].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-100-continue].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#100].
  #
  class HTTPContinue < HTTPInformation
    HAS_BODY = false
  end

  # Response class for <tt>Switching Protocol</tt> responses (status code 101).
  #
  # The <tt>Switching Protocol<tt> response indicates that the server has received
  # a request to switch protocols, and has agreed to do so.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/101].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-101-switching-protocols].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#101].
  #
  class HTTPSwitchProtocol < HTTPInformation
    HAS_BODY = false
  end

  # Response class for +Processing+ responses (status code 102).
  #
  # The +Processing+ response indicates that the server has received
  # and is processing the request, but no response is available yet.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 2518}[https://www.rfc-editor.org/rfc/rfc2518#section-10.1].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#102].
  #
  class HTTPProcessing < HTTPInformation
    HAS_BODY = false
  end

  # Response class for <tt>Early Hints</tt> responses (status code 103).
  #
  # The <tt>Early Hints</tt> indicates that the server has received
  # and is processing the request, and contains certain headers;
  # the final response is not available yet.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/103].
  # - {RFC 8297}[https://www.rfc-editor.org/rfc/rfc8297.html#section-2].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#103].
  #
  class HTTPEarlyHints < HTTPInformation
    HAS_BODY = false
  end

  # Response class for +OK+ responses (status code 200).
  #
  # The +OK+ response indicates that the server has received
  # a request and has responded successfully.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-200-ok].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#200].
  #
  class HTTPOK < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for +Created+ responses (status code 201).
  #
  # The +Created+ response indicates that the server has received
  # and has fulfilled a request to create a new resource.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/201].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-201-created].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#201].
  #
  class HTTPCreated < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for +Accepted+ responses (status code 202).
  #
  # The +Accepted+ response indicates that the server has received
  # and is processing a request, but the processing has not yet been completed.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/202].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-202-accepted].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#202].
  #
  class HTTPAccepted < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Non-Authoritative Information</tt> responses (status code 203).
  #
  # The <tt>Non-Authoritative Information</tt> response indicates that the server
  # is a transforming proxy (such as a Web accelerator)
  # that received a 200 OK response from its origin,
  # and is returning a modified version of the origin's response.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/203].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-203-non-authoritative-infor].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#203].
  #
  class HTTPNonAuthoritativeInformation < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>No Content</tt> responses (status code 204).
  #
  # The <tt>No Content</tt> response indicates that the server
  # successfully processed the request, and is not returning any content.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/204].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-204-no-content].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#204].
  #
  class HTTPNoContent < HTTPSuccess
    HAS_BODY = false
  end

  # Response class for <tt>Reset Content</tt> responses (status code 205).
  #
  # The <tt>Reset Content</tt> response indicates that the server
  # successfully processed the request,
  # asks that the client reset its document view, and is not returning any content.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/205].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-205-reset-content].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#205].
  #
  class HTTPResetContent < HTTPSuccess
    HAS_BODY = false
  end

  # Response class for <tt>Partial Content</tt> responses (status code 206).
  #
  # The <tt>Partial Content</tt> response indicates that the server is delivering
  # only part of the resource (byte serving)
  # due to a Range header in the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/206].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-206-partial-content].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#206].
  #
  class HTTPPartialContent < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Multi-Status (WebDAV)</tt> responses (status code 207).
  #
  # The <tt>Multi-Status (WebDAV)</tt> response indicates that the server
  # has received the request,
  # and that the message body can contain a number of separate response codes.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 4818}[https://www.rfc-editor.org/rfc/rfc4918#section-11.1].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#207].
  #
  class HTTPMultiStatus < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Already Reported (WebDAV)</tt> responses (status code 208).
  #
  # The <tt>Already Reported (WebDAV)</tt> response indicates that the server
  # has received the request,
  # and that the members of a DAV binding have already been enumerated
  # in a preceding part of the (multi-status) response,
  # and are not being included again.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 5842}[https://www.rfc-editor.org/rfc/rfc5842.html#section-7.1].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#208].
  #
  class HTTPAlreadyReported < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>IM Used</tt> responses (status code 226).
  #
  # The <tt>IM Used</tt> response indicates that the server has fulfilled a request
  # for the resource, and the response is a representation of the result
  # of one or more instance-manipulations applied to the current instance.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 3229}[https://www.rfc-editor.org/rfc/rfc3229.html#section-10.4.1].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#226].
  #
  class HTTPIMUsed < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Multiple Choices</tt> responses (status code 300).
  #
  # The <tt>Multiple Choices</tt> response indicates that the server
  # offers multiple options for the resource from which the client may choose.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/300].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-300-multiple-choices].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#300].
  #
  class HTTPMultipleChoices < HTTPRedirection
    HAS_BODY = true
  end
  HTTPMultipleChoice = HTTPMultipleChoices

  # Response class for <tt>Moved Permanently</tt> responses (status code 301).
  #
  # The <tt>Moved Permanently</tt> response indicates that links or records
  # returning this response should be updated to use the given URL.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/301].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-301-moved-permanently].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#301].
  #
  class HTTPMovedPermanently < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Found</tt> responses (status code 302).
  #
  # The <tt>Found</tt> response indicates that the client
  # should look at (browse to) another URL.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/302].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-302-found].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#302].
  #
  class HTTPFound < HTTPRedirection
    HAS_BODY = true
  end
  HTTPMovedTemporarily = HTTPFound

  # Response class for <tt>See Other</tt> responses (status code 303).
  #
  # The response to the request can be found under another Gem::URI using the GET method.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/303].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-303-see-other].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#303].
  #
  class HTTPSeeOther < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Not Modified</tt> responses (status code 304).
  #
  # Indicates that the resource has not been modified since the version
  # specified by the request headers.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/304].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-304-not-modified].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#304].
  #
  class HTTPNotModified < HTTPRedirection
    HAS_BODY = false
  end

  # Response class for <tt>Use Proxy</tt> responses (status code 305).
  #
  # The requested resource is available only through a proxy,
  # whose address is provided in the response.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-305-use-proxy].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#305].
  #
  class HTTPUseProxy < HTTPRedirection
    HAS_BODY = false
  end

  # Response class for <tt>Temporary Redirect</tt> responses (status code 307).
  #
  # The request should be repeated with another Gem::URI;
  # however, future requests should still use the original Gem::URI.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/307].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-307-temporary-redirect].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#307].
  #
  class HTTPTemporaryRedirect < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Permanent Redirect</tt> responses (status code 308).
  #
  # This and all future requests should be directed to the given Gem::URI.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/308].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-308-permanent-redirect].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#308].
  #
  class HTTPPermanentRedirect < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Bad Request</tt> responses (status code 400).
  #
  # The server cannot or will not process the request due to an apparent client error.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/400].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-400-bad-request].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#400].
  #
  class HTTPBadRequest < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unauthorized</tt> responses (status code 401).
  #
  # Authentication is required, but either was not provided or failed.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/401].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-401-unauthorized].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#401].
  #
  class HTTPUnauthorized < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Payment Required</tt> responses (status code 402).
  #
  # Reserved for future use.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/402].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-402-payment-required].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#402].
  #
  class HTTPPaymentRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Forbidden</tt> responses (status code 403).
  #
  # The request contained valid data and was understood by the server,
  # but the server is refusing action.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/403].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-403-forbidden].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#403].
  #
  class HTTPForbidden < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Not Found</tt> responses (status code 404).
  #
  # The requested resource could not be found but may be available in the future.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/404].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-404-not-found].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#404].
  #
  class HTTPNotFound < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Method Not Allowed</tt> responses (status code 405).
  #
  # The request method is not supported for the requested resource.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/405].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-405-method-not-allowed].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#405].
  #
  class HTTPMethodNotAllowed < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Not Acceptable</tt> responses (status code 406).
  #
  # The requested resource is capable of generating only content
  # that not acceptable according to the Accept headers sent in the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/406].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-406-not-acceptable].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#406].
  #
  class HTTPNotAcceptable < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Proxy Authentication Required</tt> responses (status code 407).
  #
  # The client must first authenticate itself with the proxy.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/407].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-407-proxy-authentication-re].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#407].
  #
  class HTTPProxyAuthenticationRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Request Gem::Timeout</tt> responses (status code 408).
  #
  # The server timed out waiting for the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/408].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-408-request-timeout].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#408].
  #
  class HTTPRequestTimeout < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestTimeOut = HTTPRequestTimeout

  # Response class for <tt>Conflict</tt> responses (status code 409).
  #
  # The request could not be processed because of conflict in the current state of the resource.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/409].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-409-conflict].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#409].
  #
  class HTTPConflict < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Gone</tt> responses (status code 410).
  #
  # The resource requested was previously in use but is no longer available
  # and will not be available again.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/410].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-410-gone].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#410].
  #
  class HTTPGone < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Length Required</tt> responses (status code 411).
  #
  # The request did not specify the length of its content,
  # which is required by the requested resource.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/411].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-411-length-required].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#411].
  #
  class HTTPLengthRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Precondition Failed</tt> responses (status code 412).
  #
  # The server does not meet one of the preconditions
  # specified in the request headers.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/412].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-412-precondition-failed].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#412].
  #
  class HTTPPreconditionFailed < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Payload Too Large</tt> responses (status code 413).
  #
  # The request is larger than the server is willing or able to process.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/413].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-413-content-too-large].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#413].
  #
  class HTTPPayloadTooLarge < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestEntityTooLarge = HTTPPayloadTooLarge

  # Response class for <tt>Gem::URI Too Long</tt> responses (status code 414).
  #
  # The Gem::URI provided was too long for the server to process.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/414].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-414-uri-too-long].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#414].
  #
  class HTTPURITooLong < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestURITooLong = HTTPURITooLong
  HTTPRequestURITooLarge = HTTPRequestURITooLong

  # Response class for <tt>Unsupported Media Type</tt> responses (status code 415).
  #
  # The request entity has a media type which the server or resource does not support.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/415].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-415-unsupported-media-type].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#415].
  #
  class HTTPUnsupportedMediaType < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Range Not Satisfiable</tt> responses (status code 416).
  #
  # The request entity has a media type which the server or resource does not support.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/416].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-416-range-not-satisfiable].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#416].
  #
  class HTTPRangeNotSatisfiable < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestedRangeNotSatisfiable = HTTPRangeNotSatisfiable

  # Response class for <tt>Expectation Failed</tt> responses (status code 417).
  #
  # The server cannot meet the requirements of the Expect request-header field.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/417].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-417-expectation-failed].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#417].
  #
  class HTTPExpectationFailed < HTTPClientError
    HAS_BODY = true
  end

  # 418 I'm a teapot - RFC 2324; a joke RFC
  # See https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#418.

  # 420 Enhance Your Calm - Twitter

  # Response class for <tt>Misdirected Request</tt> responses (status code 421).
  #
  # The request was directed at a server that is not able to produce a response.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-421-misdirected-request].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#421].
  #
  class HTTPMisdirectedRequest < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unprocessable Entity</tt> responses (status code 422).
  #
  # The request was well-formed but had semantic errors.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/422].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-422-unprocessable-content].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#422].
  #
  class HTTPUnprocessableEntity < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Locked (WebDAV)</tt> responses (status code 423).
  #
  # The requested resource is locked.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 4918}[https://www.rfc-editor.org/rfc/rfc4918#section-11.3].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#423].
  #
  class HTTPLocked < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Failed Dependency (WebDAV)</tt> responses (status code 424).
  #
  # The request failed because it depended on another request and that request failed.
  # See {424 Failed Dependency (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#424].
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {RFC 4918}[https://www.rfc-editor.org/rfc/rfc4918#section-11.4].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#424].
  #
  class HTTPFailedDependency < HTTPClientError
    HAS_BODY = true
  end

  # 425 Too Early
  # https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#425.

  # Response class for <tt>Upgrade Required</tt> responses (status code 426).
  #
  # The client should switch to the protocol given in the Upgrade header field.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/426].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-426-upgrade-required].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#426].
  #
  class HTTPUpgradeRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Precondition Required</tt> responses (status code 428).
  #
  # The origin server requires the request to be conditional.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/428].
  # - {RFC 6585}[https://www.rfc-editor.org/rfc/rfc6585#section-3].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#428].
  #
  class HTTPPreconditionRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Too Many Requests</tt> responses (status code 429).
  #
  # The user has sent too many requests in a given amount of time.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/429].
  # - {RFC 6585}[https://www.rfc-editor.org/rfc/rfc6585#section-4].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#429].
  #
  class HTTPTooManyRequests < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Request Header Fields Too Large</tt> responses (status code 431).
  #
  # An individual header field is too large,
  # or all the header fields collectively, are too large.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/431].
  # - {RFC 6585}[https://www.rfc-editor.org/rfc/rfc6585#section-5].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#431].
  #
  class HTTPRequestHeaderFieldsTooLarge < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unavailable For Legal Reasons</tt> responses (status code 451).
  #
  # A server operator has received a legal demand to deny access to a resource or to a set of resources
  # that includes the requested resource.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/451].
  # - {RFC 7725}[https://www.rfc-editor.org/rfc/rfc7725.html#section-3].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#451].
  #
  class HTTPUnavailableForLegalReasons < HTTPClientError
    HAS_BODY = true
  end
  # 444 No Response - Nginx
  # 449 Retry With - Microsoft
  # 450 Blocked by Windows Parental Controls - Microsoft
  # 499 Client Closed Request - Nginx

  # Response class for <tt>Internal Server Error</tt> responses (status code 500).
  #
  # An unexpected condition was encountered and no more specific message is suitable.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/500].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-500-internal-server-error].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#500].
  #
  class HTTPInternalServerError < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Not Implemented</tt> responses (status code 501).
  #
  # The server either does not recognize the request method,
  # or it lacks the ability to fulfil the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/501].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-501-not-implemented].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#501].
  #
  class HTTPNotImplemented < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Bad Gateway</tt> responses (status code 502).
  #
  # The server was acting as a gateway or proxy
  # and received an invalid response from the upstream server.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/502].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-502-bad-gateway].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#502].
  #
  class HTTPBadGateway < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Service Unavailable</tt> responses (status code 503).
  #
  # The server cannot handle the request
  # (because it is overloaded or down for maintenance).
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-503-service-unavailable].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#503].
  #
  class HTTPServiceUnavailable < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Gateway Gem::Timeout</tt> responses (status code 504).
  #
  # The server was acting as a gateway or proxy
  # and did not receive a timely response from the upstream server.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/504].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-504-gateway-timeout].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#504].
  #
  class HTTPGatewayTimeout < HTTPServerError
    HAS_BODY = true
  end
  HTTPGatewayTimeOut = HTTPGatewayTimeout

  # Response class for <tt>HTTP Version Not Supported</tt> responses (status code 505).
  #
  # The server does not support the HTTP version used in the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/505].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-505-http-version-not-suppor].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#505].
  #
  class HTTPVersionNotSupported < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Variant Also Negotiates</tt> responses (status code 506).
  #
  # Transparent content negotiation for the request results in a circular reference.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/506].
  # - {RFC 2295}[https://www.rfc-editor.org/rfc/rfc2295#section-8.1].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#506].
  #
  class HTTPVariantAlsoNegotiates < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Insufficient Storage (WebDAV)</tt> responses (status code 507).
  #
  # The server is unable to store the representation needed to complete the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/507].
  # - {RFC 4918}[https://www.rfc-editor.org/rfc/rfc4918#section-11.5].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#507].
  #
  class HTTPInsufficientStorage < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Loop Detected (WebDAV)</tt> responses (status code 508).
  #
  # The server detected an infinite loop while processing the request.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/508].
  # - {RFC 5942}[https://www.rfc-editor.org/rfc/rfc5842.html#section-7.2].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#508].
  #
  class HTTPLoopDetected < HTTPServerError
    HAS_BODY = true
  end
  # 509 Bandwidth Limit Exceeded - Apache bw/limited extension

  # Response class for <tt>Not Extended</tt> responses (status code 510).
  #
  # Further extensions to the request are required for the server to fulfill it.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/510].
  # - {RFC 2774}[https://www.rfc-editor.org/rfc/rfc2774.html#section-7].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#510].
  #
  class HTTPNotExtended < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Network Authentication Required</tt> responses (status code 511).
  #
  # The client needs to authenticate to gain network access.
  #
  # :include: doc/net-http/included_getters.rdoc
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/511].
  # - {RFC 6585}[https://www.rfc-editor.org/rfc/rfc6585#section-6].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#511].
  #
  class HTTPNetworkAuthenticationRequired < HTTPServerError
    HAS_BODY = true
  end

end

class Gem::Net::HTTPResponse
  CODE_CLASS_TO_OBJ = {
    '1' => Gem::Net::HTTPInformation,
    '2' => Gem::Net::HTTPSuccess,
    '3' => Gem::Net::HTTPRedirection,
    '4' => Gem::Net::HTTPClientError,
    '5' => Gem::Net::HTTPServerError
  }
  CODE_TO_OBJ = {
    '100' => Gem::Net::HTTPContinue,
    '101' => Gem::Net::HTTPSwitchProtocol,
    '102' => Gem::Net::HTTPProcessing,
    '103' => Gem::Net::HTTPEarlyHints,

    '200' => Gem::Net::HTTPOK,
    '201' => Gem::Net::HTTPCreated,
    '202' => Gem::Net::HTTPAccepted,
    '203' => Gem::Net::HTTPNonAuthoritativeInformation,
    '204' => Gem::Net::HTTPNoContent,
    '205' => Gem::Net::HTTPResetContent,
    '206' => Gem::Net::HTTPPartialContent,
    '207' => Gem::Net::HTTPMultiStatus,
    '208' => Gem::Net::HTTPAlreadyReported,
    '226' => Gem::Net::HTTPIMUsed,

    '300' => Gem::Net::HTTPMultipleChoices,
    '301' => Gem::Net::HTTPMovedPermanently,
    '302' => Gem::Net::HTTPFound,
    '303' => Gem::Net::HTTPSeeOther,
    '304' => Gem::Net::HTTPNotModified,
    '305' => Gem::Net::HTTPUseProxy,
    '307' => Gem::Net::HTTPTemporaryRedirect,
    '308' => Gem::Net::HTTPPermanentRedirect,

    '400' => Gem::Net::HTTPBadRequest,
    '401' => Gem::Net::HTTPUnauthorized,
    '402' => Gem::Net::HTTPPaymentRequired,
    '403' => Gem::Net::HTTPForbidden,
    '404' => Gem::Net::HTTPNotFound,
    '405' => Gem::Net::HTTPMethodNotAllowed,
    '406' => Gem::Net::HTTPNotAcceptable,
    '407' => Gem::Net::HTTPProxyAuthenticationRequired,
    '408' => Gem::Net::HTTPRequestTimeout,
    '409' => Gem::Net::HTTPConflict,
    '410' => Gem::Net::HTTPGone,
    '411' => Gem::Net::HTTPLengthRequired,
    '412' => Gem::Net::HTTPPreconditionFailed,
    '413' => Gem::Net::HTTPPayloadTooLarge,
    '414' => Gem::Net::HTTPURITooLong,
    '415' => Gem::Net::HTTPUnsupportedMediaType,
    '416' => Gem::Net::HTTPRangeNotSatisfiable,
    '417' => Gem::Net::HTTPExpectationFailed,
    '421' => Gem::Net::HTTPMisdirectedRequest,
    '422' => Gem::Net::HTTPUnprocessableEntity,
    '423' => Gem::Net::HTTPLocked,
    '424' => Gem::Net::HTTPFailedDependency,
    '426' => Gem::Net::HTTPUpgradeRequired,
    '428' => Gem::Net::HTTPPreconditionRequired,
    '429' => Gem::Net::HTTPTooManyRequests,
    '431' => Gem::Net::HTTPRequestHeaderFieldsTooLarge,
    '451' => Gem::Net::HTTPUnavailableForLegalReasons,

    '500' => Gem::Net::HTTPInternalServerError,
    '501' => Gem::Net::HTTPNotImplemented,
    '502' => Gem::Net::HTTPBadGateway,
    '503' => Gem::Net::HTTPServiceUnavailable,
    '504' => Gem::Net::HTTPGatewayTimeout,
    '505' => Gem::Net::HTTPVersionNotSupported,
    '506' => Gem::Net::HTTPVariantAlsoNegotiates,
    '507' => Gem::Net::HTTPInsufficientStorage,
    '508' => Gem::Net::HTTPLoopDetected,
    '510' => Gem::Net::HTTPNotExtended,
    '511' => Gem::Net::HTTPNetworkAuthenticationRequired,
  }
end
