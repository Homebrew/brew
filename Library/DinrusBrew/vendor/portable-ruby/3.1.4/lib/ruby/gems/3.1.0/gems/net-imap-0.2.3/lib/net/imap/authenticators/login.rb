# frozen_string_literal: true

# Authenticator for the "+LOGIN+" SASL mechanism.  See Net::IMAP#authenticate.
#
# +LOGIN+ authentication sends the password in cleartext.
# RFC3501[https://tools.ietf.org/html/rfc3501] encourages servers to disable
# cleartext authentication until after TLS has been negotiated.
# RFC8314[https://tools.ietf.org/html/rfc8314] recommends TLS version 1.2 or
# greater be used for all traffic, and deprecate cleartext access ASAP.  +LOGIN+
# can be secured by TLS encryption.
#
# == Deprecated
#
# The {SASL mechanisms
# registry}[https://www.iana.org/assignments/sasl-mechanisms/sasl-mechanisms.xhtml]
# marks "LOGIN" as obsoleted in favor of "PLAIN".  It is included here for
# compatibility with existing servers.  See
# {draft-murchison-sasl-login}[https://www.iana.org/go/draft-murchison-sasl-login]
# for both specification and deprecation.
class Net::IMAP::LoginAuthenticator
  def process(data)
    case @state
    when STATE_USER
      @state = STATE_PASSWORD
      return @user
    when STATE_PASSWORD
      return @password
    end
  end

  private

  STATE_USER = :USER
  STATE_PASSWORD = :PASSWORD

  def initialize(user, password)
    @user = user
    @password = password
    @state = STATE_USER
  end

  Net::IMAP.add_authenticator "LOGIN", self
end
