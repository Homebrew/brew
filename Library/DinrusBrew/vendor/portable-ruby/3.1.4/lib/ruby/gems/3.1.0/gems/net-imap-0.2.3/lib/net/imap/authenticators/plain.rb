# frozen_string_literal: true

# Authenticator for the "+PLAIN+" SASL mechanism, specified in
# RFC4616[https://tools.ietf.org/html/rfc4616].  See Net::IMAP#authenticate.
#
# +PLAIN+ authentication sends the password in cleartext.
# RFC3501[https://tools.ietf.org/html/rfc3501] encourages servers to disable
# cleartext authentication until after TLS has been negotiated.
# RFC8314[https://tools.ietf.org/html/rfc8314] recommends TLS version 1.2 or
# greater be used for all traffic, and deprecate cleartext access ASAP.  +PLAIN+
# can be secured by TLS encryption.
class Net::IMAP::PlainAuthenticator

  def process(data)
    return "#@authzid\0#@username\0#@password"
  end

  # :nodoc:
  NULL = -"\0".b

  private

  # +username+ is the authentication identity, the identity whose +password+ is
  # used.  +username+ is referred to as +authcid+ by
  # RFC4616[https://tools.ietf.org/html/rfc4616].
  #
  # +authzid+ is the authorization identity (identity to act as).  It can
  # usually be left blank. When +authzid+ is left blank (nil or empty string)
  # the server will derive an identity from the credentials and use that as the
  # authorization identity.
  def initialize(username, password, authzid: nil)
    raise ArgumentError, "username contains NULL" if username&.include?(NULL)
    raise ArgumentError, "password contains NULL" if password&.include?(NULL)
    raise ArgumentError, "authzid  contains NULL" if authzid&.include?(NULL)
    @username = username
    @password = password
    @authzid  = authzid
  end

  Net::IMAP.add_authenticator "PLAIN", self
end
