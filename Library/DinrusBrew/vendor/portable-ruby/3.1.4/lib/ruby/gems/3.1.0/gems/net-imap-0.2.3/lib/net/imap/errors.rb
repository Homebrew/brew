# frozen_string_literal: true

module Net
  class IMAP < Protocol

    # Superclass of IMAP errors.
    class Error < StandardError
    end

    # Error raised when data is in the incorrect format.
    class DataFormatError < Error
    end

    # Error raised when a response from the server is non-parseable.
    class ResponseParseError < Error
    end

    # Superclass of all errors used to encapsulate "fail" responses
    # from the server.
    class ResponseError < Error

      # The response that caused this error
      attr_accessor :response

      def initialize(response)
        @response = response

        super @response.data.text
      end

    end

    # Error raised upon a "NO" response from the server, indicating
    # that the client command could not be completed successfully.
    class NoResponseError < ResponseError
    end

    # Error raised upon a "BAD" response from the server, indicating
    # that the client command violated the IMAP protocol, or an internal
    # server failure has occurred.
    class BadResponseError < ResponseError
    end

    # Error raised upon a "BYE" response from the server, indicating
    # that the client is not being allowed to login, or has been timed
    # out due to inactivity.
    class ByeResponseError < ResponseError
    end

    # Error raised upon an unknown response from the server.
    class UnknownResponseError < ResponseError
    end

    RESPONSE_ERRORS = Hash.new(ResponseError)
    RESPONSE_ERRORS["NO"] = NoResponseError
    RESPONSE_ERRORS["BAD"] = BadResponseError

  end
end
