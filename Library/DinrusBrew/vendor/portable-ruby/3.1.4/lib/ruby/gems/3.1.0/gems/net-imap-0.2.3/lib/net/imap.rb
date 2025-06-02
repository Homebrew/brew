# frozen_string_literal: true
#
# = net/imap.rb
#
# Copyright (C) 2000  Shugo Maeda <shugo@ruby-lang.org>
#
# This library is distributed under the terms of the Ruby license.
# You can freely distribute/modify this library.
#
# Documentation: Shugo Maeda, with RDoc conversion and overview by William
# Webber.
#
# See Net::IMAP for documentation.
#

require "socket"
require "monitor"
require 'net/protocol'
begin
  require "openssl"
rescue LoadError
end

module Net

  #
  # Net::IMAP implements Internet Message Access Protocol (IMAP) client
  # functionality.  The protocol is described in
  # [IMAP[https://tools.ietf.org/html/rfc3501]].
  #
  # == IMAP Overview
  #
  # An \IMAP client connects to a server, and then authenticates
  # itself using either #authenticate or #login.  Having
  # authenticated itself, there is a range of commands
  # available to it.  Most work with mailboxes, which may be
  # arranged in an hierarchical namespace, and each of which
  # contains zero or more messages.  How this is implemented on
  # the server is implementation-dependent; on a UNIX server, it
  # will frequently be implemented as files in mailbox format
  # within a hierarchy of directories.
  #
  # To work on the messages within a mailbox, the client must
  # first select that mailbox, using either #select or (for
  # read-only access) #examine.  Once the client has successfully
  # selected a mailbox, they enter _selected_ state, and that
  # mailbox becomes the _current_ mailbox, on which mail-item
  # related commands implicitly operate.
  #
  # Messages have two sorts of identifiers: message sequence
  # numbers and UIDs.
  #
  # Message sequence numbers number messages within a mailbox
  # from 1 up to the number of items in the mailbox.  If a new
  # message arrives during a session, it receives a sequence
  # number equal to the new size of the mailbox.  If messages
  # are expunged from the mailbox, remaining messages have their
  # sequence numbers "shuffled down" to fill the gaps.
  #
  # UIDs, on the other hand, are permanently guaranteed not to
  # identify another message within the same mailbox, even if
  # the existing message is deleted.  UIDs are required to
  # be assigned in ascending (but not necessarily sequential)
  # order within a mailbox; this means that if a non-IMAP client
  # rearranges the order of mailitems within a mailbox, the
  # UIDs have to be reassigned.  An \IMAP client thus cannot
  # rearrange message orders.
  #
  # == Examples of Usage
  #
  # === List sender and subject of all recent messages in the default mailbox
  #
  #   imap = Net::IMAP.new('mail.example.com')
  #   imap.authenticate('LOGIN', 'joe_user', 'joes_password')
  #   imap.examine('INBOX')
  #   imap.search(["RECENT"]).each do |message_id|
  #     envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
  #     puts "#{envelope.from[0].name}: \t#{envelope.subject}"
  #   end
  #
  # === Move all messages from April 2003 from "Mail/sent-mail" to "Mail/sent-apr03"
  #
  #   imap = Net::IMAP.new('mail.example.com')
  #   imap.authenticate('LOGIN', 'joe_user', 'joes_password')
  #   imap.select('Mail/sent-mail')
  #   if not imap.list('Mail/', 'sent-apr03')
  #     imap.create('Mail/sent-apr03')
  #   end
  #   imap.search(["BEFORE", "30-Apr-2003", "SINCE", "1-Apr-2003"]).each do |message_id|
  #     imap.copy(message_id, "Mail/sent-apr03")
  #     imap.store(message_id, "+FLAGS", [:Deleted])
  #   end
  #   imap.expunge
  #
  # == Thread Safety
  #
  # Net::IMAP supports concurrent threads. For example,
  #
  #   imap = Net::IMAP.new("imap.foo.net", "imap2")
  #   imap.authenticate("cram-md5", "bar", "password")
  #   imap.select("inbox")
  #   fetch_thread = Thread.start { imap.fetch(1..-1, "UID") }
  #   search_result = imap.search(["BODY", "hello"])
  #   fetch_result = fetch_thread.value
  #   imap.disconnect
  #
  # This script invokes the FETCH command and the SEARCH command concurrently.
  #
  # == Errors
  #
  # An IMAP server can send three different types of responses to indicate
  # failure:
  #
  # NO:: the attempted command could not be successfully completed.  For
  #      instance, the username/password used for logging in are incorrect;
  #      the selected mailbox does not exist; etc.
  #
  # BAD:: the request from the client does not follow the server's
  #       understanding of the IMAP protocol.  This includes attempting
  #       commands from the wrong client state; for instance, attempting
  #       to perform a SEARCH command without having SELECTed a current
  #       mailbox.  It can also signal an internal server
  #       failure (such as a disk crash) has occurred.
  #
  # BYE:: the server is saying goodbye.  This can be part of a normal
  #       logout sequence, and can be used as part of a login sequence
  #       to indicate that the server is (for some reason) unwilling
  #       to accept your connection.  As a response to any other command,
  #       it indicates either that the server is shutting down, or that
  #       the server is timing out the client connection due to inactivity.
  #
  # These three error response are represented by the errors
  # Net::IMAP::NoResponseError, Net::IMAP::BadResponseError, and
  # Net::IMAP::ByeResponseError, all of which are subclasses of
  # Net::IMAP::ResponseError.  Essentially, all methods that involve
  # sending a request to the server can generate one of these errors.
  # Only the most pertinent instances have been documented below.
  #
  # Because the IMAP class uses Sockets for communication, its methods
  # are also susceptible to the various errors that can occur when
  # working with sockets.  These are generally represented as
  # Errno errors.  For instance, any method that involves sending a
  # request to the server and/or receiving a response from it could
  # raise an Errno::EPIPE error if the network connection unexpectedly
  # goes down.  See the socket(7), ip(7), tcp(7), socket(2), connect(2),
  # and associated man pages.
  #
  # Finally, a Net::IMAP::DataFormatError is thrown if low-level data
  # is found to be in an incorrect format (for instance, when converting
  # between UTF-8 and UTF-16), and Net::IMAP::ResponseParseError is
  # thrown if a server response is non-parseable.
  #
  #
  # == References
  #
  # [[IMAP[https://tools.ietf.org/html/rfc3501]]]
  #    Crispin, M. "INTERNET MESSAGE ACCESS PROTOCOL - \VERSION 4rev1",
  #    RFC-3501[https://tools.ietf.org/html/rfc3501], March 2003.  (Note:
  #    obsoletes RFC-2060[https://tools.ietf.org/html/rfc2060], December 1996.)
  #
  # [[LANGUAGE-TAGS[https://tools.ietf.org/html/rfc1766]]]
  #    Phillips, A. and Davis, M. "Tags for Identifying Languages",
  #    RFC-5646[https://tools.ietf.org/html/rfc5646], September 2009.
  #    (Note: obsoletes
  #    RFC-3066[https://tools.ietf.org/html/rfc3066], January 2001,
  #    RFC-4646[https://tools.ietf.org/html/rfc4646], September 2006, and
  #    RFC-1766[https://tools.ietf.org/html/rfc1766], March 1995.)
  #
  # [[MD5[https://tools.ietf.org/html/rfc1864]]]
  #    Myers, J. and M. Rose, "The Content-MD5 Header Field",
  #    RFC-1864[https://tools.ietf.org/html/rfc1864], October 1995.
  #
  # [[MIME-IMB[https://tools.ietf.org/html/rfc2045]]]
  #    Freed, N. and N. Borenstein, "MIME (Multipurpose Internet
  #    Mail Extensions) Part One: Format of Internet Message Bodies",
  #    RFC-2045[https://tools.ietf.org/html/rfc2045], November 1996.
  #
  # [[RFC-5322[https://tools.ietf.org/html/rfc5322]]]
  #    Resnick, P., "Internet Message Format",
  #    RFC-5322[https://tools.ietf.org/html/rfc5322], October 2008.
  #    (Note: obsoletes
  #    RFC-2822[https://tools.ietf.org/html/rfc2822], April 2001, and
  #    RFC-822[https://tools.ietf.org/html/rfc822], August 1982.)
  #
  # [[EXT-QUOTA[https://tools.ietf.org/html/rfc2087]]]
  #    Myers, J., "IMAP4 QUOTA extension",
  #    RFC-2087[https://tools.ietf.org/html/rfc2087], January 1997.
  #
  # [[EXT-NAMESPACE[https://tools.ietf.org/html/rfc2342]]]
  #    Gahrns, M. and Newman, C., "IMAP4 Namespace",
  #    RFC-2342[https://tools.ietf.org/html/rfc2342], May 1998.
  #
  # [[EXT-ID[https://tools.ietf.org/html/rfc2971]]]
  #    Showalter, T., "IMAP4 ID extension",
  #    RFC-2971[https://tools.ietf.org/html/rfc2971], October 2000.
  #
  # [[EXT-ACL[https://tools.ietf.org/html/rfc4314]]]
  #    Melnikov, A., "IMAP4 ACL extension",
  #    RFC-4314[https://tools.ietf.org/html/rfc4314], December 2005.  (Note:
  #    obsoletes RFC-2086[https://tools.ietf.org/html/rfc2086], January 1997.)
  #
  # [[EXT-SORT-THREAD[https://tools.ietf.org/html/rfc5256]]]
  #    Crispin, M. and Muchison, K., "INTERNET MESSAGE ACCESS PROTOCOL - SORT
  #    and THREAD Extensions", RFC-5256[https://tools.ietf.org/html/rfc5256],
  #    June 2008.
  #
  # [[EXT-MOVE[https://tools.ietf.org/html/rfc6851]]]
  #    Gulbrandsen, A. and Freed, N., "Internet Message Access Protocol (\IMAP) -
  #    MOVE Extension", RFC-6851[https://tools.ietf.org/html/rfc6851], January
  #    2013.
  #
  # [[OSSL]]
  #    http://www.openssl.org
  #
  # [[RSSL]]
  #    http://savannah.gnu.org/projects/rubypki
  #
  # [[UTF7[https://tools.ietf.org/html/rfc2152]]]
  #    Goldsmith, D. and Davis, M., "UTF-7: A Mail-Safe Transformation Format of
  #    Unicode", RFC-2152[https://tools.ietf.org/html/rfc2152], May 1997.
  #
  class IMAP < Protocol
    VERSION = "0.2.3"

    include MonitorMixin
    if defined?(OpenSSL::SSL)
      include OpenSSL
      include SSL
    end

    #  Returns an initial greeting response from the server.
    attr_reader :greeting

    # Returns recorded untagged responses.  For example:
    #
    #   imap.select("inbox")
    #   p imap.responses["EXISTS"][-1]
    #   #=> 2
    #   p imap.responses["UIDVALIDITY"][-1]
    #   #=> 968263756
    attr_reader :responses

    # Returns all response handlers.
    attr_reader :response_handlers

    # Seconds to wait until a connection is opened.
    # If the IMAP object cannot open a connection within this time,
    # it raises a Net::OpenTimeout exception. The default value is 30 seconds.
    attr_reader :open_timeout

    # Seconds to wait until an IDLE response is received.
    attr_reader :idle_response_timeout

    # The thread to receive exceptions.
    attr_accessor :client_thread

    # Returns the debug mode.
    def self.debug
      return @@debug
    end

    # Sets the debug mode.
    def self.debug=(val)
      return @@debug = val
    end

    # The default port for IMAP connections, port 143
    def self.default_port
      return PORT
    end

    # The default port for IMAPS connections, port 993
    def self.default_tls_port
      return SSL_PORT
    end

    class << self
      alias default_imap_port default_port
      alias default_imaps_port default_tls_port
      alias default_ssl_port default_tls_port
    end

    # Disconnects from the server.
    def disconnect
      return if disconnected?
      begin
        begin
          # try to call SSL::SSLSocket#io.
          @sock.io.shutdown
        rescue NoMethodError
          # @sock is not an SSL::SSLSocket.
          @sock.shutdown
        end
      rescue Errno::ENOTCONN
        # ignore `Errno::ENOTCONN: Socket is not connected' on some platforms.
      rescue Exception => e
        @receiver_thread.raise(e)
      end
      @receiver_thread.join
      synchronize do
        @sock.close
      end
      raise e if e
    end

    # Returns true if disconnected from the server.
    def disconnected?
      return @sock.closed?
    end

    # Sends a CAPABILITY command, and returns an array of
    # capabilities that the server supports.  Each capability
    # is a string.  See [IMAP] for a list of possible
    # capabilities.
    #
    # Note that the Net::IMAP class does not modify its
    # behaviour according to the capabilities of the server;
    # it is up to the user of the class to ensure that
    # a certain capability is supported by a server before
    # using it.
    def capability
      synchronize do
        send_command("CAPABILITY")
        return @responses.delete("CAPABILITY")[-1]
      end
    end

    # Sends an ID command, and returns a hash of the server's
    # response, or nil if the server does not identify itself.
    #
    # Note that the user should first check if the server supports the ID
    # capability. For example:
    #
    #    capabilities = imap.capability
    #    if capabilities.include?("ID")
    #      id = imap.id(
    #        name: "my IMAP client (ruby)",
    #        version: MyIMAP::VERSION,
    #        "support-url": "mailto:bugs@example.com",
    #        os: RbConfig::CONFIG["host_os"],
    #      )
    #    end
    #
    # See [EXT-ID[https://tools.ietf.org/html/rfc2971]] for field definitions.
    def id(client_id=nil)
      synchronize do
        send_command("ID", ClientID.new(client_id))
        @responses.delete("ID")&.last
      end
    end

    # Sends a NOOP command to the server. It does nothing.
    def noop
      send_command("NOOP")
    end

    # Sends a LOGOUT command to inform the server that the client is
    # done with the connection.
    def logout
      send_command("LOGOUT")
    end

    # Sends a STARTTLS command to start TLS session.
    def starttls(options = {}, verify = true)
      send_command("STARTTLS") do |resp|
        if resp.kind_of?(TaggedResponse) && resp.name == "OK"
          begin
            # for backward compatibility
            certs = options.to_str
            options = create_ssl_params(certs, verify)
          rescue NoMethodError
          end
          start_tls_session(options)
        end
      end
    end

    # Sends an AUTHENTICATE command to authenticate the client.
    # The +auth_type+ parameter is a string that represents
    # the authentication mechanism to be used. Currently Net::IMAP
    # supports the authentication mechanisms:
    #
    #   LOGIN:: login using cleartext user and password.
    #   CRAM-MD5:: login with cleartext user and encrypted password
    #              (see [RFC-2195] for a full description).  This
    #              mechanism requires that the server have the user's
    #              password stored in clear-text password.
    #
    # For both of these mechanisms, there should be two +args+: username
    # and (cleartext) password.  A server may not support one or the other
    # of these mechanisms; check #capability for a capability of
    # the form "AUTH=LOGIN" or "AUTH=CRAM-MD5".
    #
    # Authentication is done using the appropriate authenticator object:
    # see +add_authenticator+ for more information on plugging in your own
    # authenticator.
    #
    # For example:
    #
    #    imap.authenticate('LOGIN', user, password)
    #
    # A Net::IMAP::NoResponseError is raised if authentication fails.
    def authenticate(auth_type, *args)
      authenticator = self.class.authenticator(auth_type, *args)
      send_command("AUTHENTICATE", auth_type) do |resp|
        if resp.instance_of?(ContinuationRequest)
          data = authenticator.process(resp.data.text.unpack("m")[0])
          s = [data].pack("m0")
          send_string_data(s)
          put_string(CRLF)
        end
      end
    end

    # Sends a LOGIN command to identify the client and carries
    # the plaintext +password+ authenticating this +user+.  Note
    # that, unlike calling #authenticate with an +auth_type+
    # of "LOGIN", #login does *not* use the login authenticator.
    #
    # A Net::IMAP::NoResponseError is raised if authentication fails.
    def login(user, password)
      send_command("LOGIN", user, password)
    end

    # Sends a SELECT command to select a +mailbox+ so that messages
    # in the +mailbox+ can be accessed.
    #
    # After you have selected a mailbox, you may retrieve the
    # number of items in that mailbox from +@responses["EXISTS"][-1]+,
    # and the number of recent messages from +@responses["RECENT"][-1]+.
    # Note that these values can change if new messages arrive
    # during a session; see #add_response_handler for a way of
    # detecting this event.
    #
    # A Net::IMAP::NoResponseError is raised if the mailbox does not
    # exist or is for some reason non-selectable.
    def select(mailbox)
      synchronize do
        @responses.clear
        send_command("SELECT", mailbox)
      end
    end

    # Sends a EXAMINE command to select a +mailbox+ so that messages
    # in the +mailbox+ can be accessed.  Behaves the same as #select,
    # except that the selected +mailbox+ is identified as read-only.
    #
    # A Net::IMAP::NoResponseError is raised if the mailbox does not
    # exist or is for some reason non-examinable.
    def examine(mailbox)
      synchronize do
        @responses.clear
        send_command("EXAMINE", mailbox)
      end
    end

    # Sends a CREATE command to create a new +mailbox+.
    #
    # A Net::IMAP::NoResponseError is raised if a mailbox with that name
    # cannot be created.
    def create(mailbox)
      send_command("CREATE", mailbox)
    end

    # Sends a DELETE command to remove the +mailbox+.
    #
    # A Net::IMAP::NoResponseError is raised if a mailbox with that name
    # cannot be deleted, either because it does not exist or because the
    # client does not have permission to delete it.
    def delete(mailbox)
      send_command("DELETE", mailbox)
    end

    # Sends a RENAME command to change the name of the +mailbox+ to
    # +newname+.
    #
    # A Net::IMAP::NoResponseError is raised if a mailbox with the
    # name +mailbox+ cannot be renamed to +newname+ for whatever
    # reason; for instance, because +mailbox+ does not exist, or
    # because there is already a mailbox with the name +newname+.
    def rename(mailbox, newname)
      send_command("RENAME", mailbox, newname)
    end

    # Sends a SUBSCRIBE command to add the specified +mailbox+ name to
    # the server's set of "active" or "subscribed" mailboxes as returned
    # by #lsub.
    #
    # A Net::IMAP::NoResponseError is raised if +mailbox+ cannot be
    # subscribed to; for instance, because it does not exist.
    def subscribe(mailbox)
      send_command("SUBSCRIBE", mailbox)
    end

    # Sends a UNSUBSCRIBE command to remove the specified +mailbox+ name
    # from the server's set of "active" or "subscribed" mailboxes.
    #
    # A Net::IMAP::NoResponseError is raised if +mailbox+ cannot be
    # unsubscribed from; for instance, because the client is not currently
    # subscribed to it.
    def unsubscribe(mailbox)
      send_command("UNSUBSCRIBE", mailbox)
    end

    # Sends a LIST command, and returns a subset of names from
    # the complete set of all names available to the client.
    # +refname+ provides a context (for instance, a base directory
    # in a directory-based mailbox hierarchy).  +mailbox+ specifies
    # a mailbox or (via wildcards) mailboxes under that context.
    # Two wildcards may be used in +mailbox+: '*', which matches
    # all characters *including* the hierarchy delimiter (for instance,
    # '/' on a UNIX-hosted directory-based mailbox hierarchy); and '%',
    # which matches all characters *except* the hierarchy delimiter.
    #
    # If +refname+ is empty, +mailbox+ is used directly to determine
    # which mailboxes to match.  If +mailbox+ is empty, the root
    # name of +refname+ and the hierarchy delimiter are returned.
    #
    # The return value is an array of +Net::IMAP::MailboxList+. For example:
    #
    #   imap.create("foo/bar")
    #   imap.create("foo/baz")
    #   p imap.list("", "foo/%")
    #   #=> [#<Net::IMAP::MailboxList attr=[:Noselect], delim="/", name="foo/">, \\
    #        #<Net::IMAP::MailboxList attr=[:Noinferiors, :Marked], delim="/", name="foo/bar">, \\
    #        #<Net::IMAP::MailboxList attr=[:Noinferiors], delim="/", name="foo/baz">]
    def list(refname, mailbox)
      synchronize do
        send_command("LIST", refname, mailbox)
        return @responses.delete("LIST")
      end
    end

    # Sends a NAMESPACE command and returns the namespaces that are available.
    # The NAMESPACE command allows a client to discover the prefixes of
    # namespaces used by a server for personal mailboxes, other users'
    # mailboxes, and shared mailboxes.
    #
    # The NAMESPACE extension predates [IMAP4rev1[https://tools.ietf.org/html/rfc2501]],
    # so most IMAP servers support it. Many popular IMAP servers are configured
    # with the default personal namespaces as `("" "/")`: no prefix and "/"
    # hierarchy delimiter. In that common case, the naive client may not have
    # any trouble naming mailboxes.
    #
    # But many servers are configured with the default personal namespace as
    # e.g. `("INBOX." ".")`, placing all personal folders under INBOX, with "."
    # as the hierarchy delimiter. If the client does not check for this, but
    # naively assumes it can use the same folder names for all servers, then
    # folder creation (and listing, moving, etc) can lead to errors.
    #
    # From RFC2342:
    #
    #    Although typically a server will support only a single Personal
    #    Namespace, and a single Other User's Namespace, circumstances exist
    #    where there MAY be multiples of these, and a client MUST be prepared
    #    for them. If a client is configured such that it is required to create
    #    a certain mailbox, there can be circumstances where it is unclear which
    #    Personal Namespaces it should create the mailbox in. In these
    #    situations a client SHOULD let the user select which namespaces to
    #    create the mailbox in.
    #
    # The user of this method should first check if the server supports the
    # NAMESPACE capability.  The return value is a +Net::IMAP::Namespaces+
    # object which has +personal+, +other+, and +shared+ fields, each an array
    # of +Net::IMAP::Namespace+ objects. These arrays will be empty when the
    # server responds with nil.
    #
    # For example:
    #
    #    capabilities = imap.capability
    #    if capabilities.include?("NAMESPACE")
    #      namespaces = imap.namespace
    #      if namespace = namespaces.personal.first
    #        prefix = namespace.prefix  # e.g. "" or "INBOX."
    #        delim  = namespace.delim   # e.g. "/" or "."
    #        # personal folders should use the prefix and delimiter
    #        imap.create(prefix + "foo")
    #        imap.create(prefix + "bar")
    #        imap.create(prefix + %w[path to my folder].join(delim))
    #      end
    #    end
    #
    # The NAMESPACE extension is described in [EXT-NAMESPACE[https://tools.ietf.org/html/rfc2342]]
    def namespace
      synchronize do
        send_command("NAMESPACE")
        return @responses.delete("NAMESPACE")[-1]
      end
    end

    # Sends a XLIST command, and returns a subset of names from
    # the complete set of all names available to the client.
    # +refname+ provides a context (for instance, a base directory
    # in a directory-based mailbox hierarchy).  +mailbox+ specifies
    # a mailbox or (via wildcards) mailboxes under that context.
    # Two wildcards may be used in +mailbox+: '*', which matches
    # all characters *including* the hierarchy delimiter (for instance,
    # '/' on a UNIX-hosted directory-based mailbox hierarchy); and '%',
    # which matches all characters *except* the hierarchy delimiter.
    #
    # If +refname+ is empty, +mailbox+ is used directly to determine
    # which mailboxes to match.  If +mailbox+ is empty, the root
    # name of +refname+ and the hierarchy delimiter are returned.
    #
    # The XLIST command is like the LIST command except that the flags
    # returned refer to the function of the folder/mailbox, e.g. :Sent
    #
    # The return value is an array of +Net::IMAP::MailboxList+. For example:
    #
    #   imap.create("foo/bar")
    #   imap.create("foo/baz")
    #   p imap.xlist("", "foo/%")
    #   #=> [#<Net::IMAP::MailboxList attr=[:Noselect], delim="/", name="foo/">, \\
    #        #<Net::IMAP::MailboxList attr=[:Noinferiors, :Marked], delim="/", name="foo/bar">, \\
    #        #<Net::IMAP::MailboxList attr=[:Noinferiors], delim="/", name="foo/baz">]
    def xlist(refname, mailbox)
      synchronize do
        send_command("XLIST", refname, mailbox)
        return @responses.delete("XLIST")
      end
    end

    # Sends the GETQUOTAROOT command along with the specified +mailbox+.
    # This command is generally available to both admin and user.
    # If this mailbox exists, it returns an array containing objects of type
    # Net::IMAP::MailboxQuotaRoot and Net::IMAP::MailboxQuota.
    #
    # The QUOTA extension is described in [EXT-QUOTA[https://tools.ietf.org/html/rfc2087]]
    def getquotaroot(mailbox)
      synchronize do
        send_command("GETQUOTAROOT", mailbox)
        result = []
        result.concat(@responses.delete("QUOTAROOT"))
        result.concat(@responses.delete("QUOTA"))
        return result
      end
    end

    # Sends the GETQUOTA command along with specified +mailbox+.
    # If this mailbox exists, then an array containing a
    # Net::IMAP::MailboxQuota object is returned.  This
    # command is generally only available to server admin.
    #
    # The QUOTA extension is described in [EXT-QUOTA[https://tools.ietf.org/html/rfc2087]]
    def getquota(mailbox)
      synchronize do
        send_command("GETQUOTA", mailbox)
        return @responses.delete("QUOTA")
      end
    end

    # Sends a SETQUOTA command along with the specified +mailbox+ and
    # +quota+.  If +quota+ is nil, then +quota+ will be unset for that
    # mailbox.  Typically one needs to be logged in as a server admin
    # for this to work.
    #
    # The QUOTA extension is described in [EXT-QUOTA[https://tools.ietf.org/html/rfc2087]]
    def setquota(mailbox, quota)
      if quota.nil?
        data = '()'
      else
        data = '(STORAGE ' + quota.to_s + ')'
      end
      send_command("SETQUOTA", mailbox, RawData.new(data))
    end

    # Sends the SETACL command along with +mailbox+, +user+ and the
    # +rights+ that user is to have on that mailbox.  If +rights+ is nil,
    # then that user will be stripped of any rights to that mailbox.
    #
    # The ACL extension is described in [EXT-ACL[https://tools.ietf.org/html/rfc4314]]
    def setacl(mailbox, user, rights)
      if rights.nil?
        send_command("SETACL", mailbox, user, "")
      else
        send_command("SETACL", mailbox, user, rights)
      end
    end

    # Send the GETACL command along with a specified +mailbox+.
    # If this mailbox exists, an array containing objects of
    # Net::IMAP::MailboxACLItem will be returned.
    #
    # The ACL extension is described in [EXT-ACL[https://tools.ietf.org/html/rfc4314]]
    def getacl(mailbox)
      synchronize do
        send_command("GETACL", mailbox)
        return @responses.delete("ACL")[-1]
      end
    end

    # Sends a LSUB command, and returns a subset of names from the set
    # of names that the user has declared as being "active" or
    # "subscribed."  +refname+ and +mailbox+ are interpreted as
    # for #list.
    #
    # The return value is an array of +Net::IMAP::MailboxList+.
    def lsub(refname, mailbox)
      synchronize do
        send_command("LSUB", refname, mailbox)
        return @responses.delete("LSUB")
      end
    end

    # Sends a STATUS command, and returns the status of the indicated
    # +mailbox+. +attr+ is a list of one or more attributes whose
    # statuses are to be requested.  Supported attributes include:
    #
    #   MESSAGES:: the number of messages in the mailbox.
    #   RECENT:: the number of recent messages in the mailbox.
    #   UNSEEN:: the number of unseen messages in the mailbox.
    #
    # The return value is a hash of attributes. For example:
    #
    #   p imap.status("inbox", ["MESSAGES", "RECENT"])
    #   #=> {"RECENT"=>0, "MESSAGES"=>44}
    #
    # A Net::IMAP::NoResponseError is raised if status values
    # for +mailbox+ cannot be returned; for instance, because it
    # does not exist.
    def status(mailbox, attr)
      synchronize do
        send_command("STATUS", mailbox, attr)
        return @responses.delete("STATUS")[-1].attr
      end
    end

    # Sends a APPEND command to append the +message+ to the end of
    # the +mailbox+. The optional +flags+ argument is an array of
    # flags initially passed to the new message.  The optional
    # +date_time+ argument specifies the creation time to assign to the
    # new message; it defaults to the current time.
    # For example:
    #
    #   imap.append("inbox", <<EOF.gsub(/\n/, "\r\n"), [:Seen], Time.now)
    #   Subject: hello
    #   From: shugo@ruby-lang.org
    #   To: shugo@ruby-lang.org
    #
    #   hello world
    #   EOF
    #
    # A Net::IMAP::NoResponseError is raised if the mailbox does
    # not exist (it is not created automatically), or if the flags,
    # date_time, or message arguments contain errors.
    def append(mailbox, message, flags = nil, date_time = nil)
      args = []
      if flags
        args.push(flags)
      end
      args.push(date_time) if date_time
      args.push(Literal.new(message))
      send_command("APPEND", mailbox, *args)
    end

    # Sends a CHECK command to request a checkpoint of the currently
    # selected mailbox.  This performs implementation-specific
    # housekeeping; for instance, reconciling the mailbox's
    # in-memory and on-disk state.
    def check
      send_command("CHECK")
    end

    # Sends a CLOSE command to close the currently selected mailbox.
    # The CLOSE command permanently removes from the mailbox all
    # messages that have the \Deleted flag set.
    def close
      send_command("CLOSE")
    end

    # Sends a EXPUNGE command to permanently remove from the currently
    # selected mailbox all messages that have the \Deleted flag set.
    def expunge
      synchronize do
        send_command("EXPUNGE")
        return @responses.delete("EXPUNGE")
      end
    end

    # Sends a SEARCH command to search the mailbox for messages that
    # match the given searching criteria, and returns message sequence
    # numbers.  +keys+ can either be a string holding the entire
    # search string, or a single-dimension array of search keywords and
    # arguments.  The following are some common search criteria;
    # see [IMAP] section 6.4.4 for a full list.
    #
    # <message set>:: a set of message sequence numbers.  ',' indicates
    #                 an interval, ':' indicates a range.  For instance,
    #                 '2,10:12,15' means "2,10,11,12,15".
    #
    # BEFORE <date>:: messages with an internal date strictly before
    #                 <date>.  The date argument has a format similar
    #                 to 8-Aug-2002.
    #
    # BODY <string>:: messages that contain <string> within their body.
    #
    # CC <string>:: messages containing <string> in their CC field.
    #
    # FROM <string>:: messages that contain <string> in their FROM field.
    #
    # NEW:: messages with the \Recent, but not the \Seen, flag set.
    #
    # NOT <search-key>:: negate the following search key.
    #
    # OR <search-key> <search-key>:: "or" two search keys together.
    #
    # ON <date>:: messages with an internal date exactly equal to <date>,
    #             which has a format similar to 8-Aug-2002.
    #
    # SINCE <date>:: messages with an internal date on or after <date>.
    #
    # SUBJECT <string>:: messages with <string> in their subject.
    #
    # TO <string>:: messages with <string> in their TO field.
    #
    # For example:
    #
    #   p imap.search(["SUBJECT", "hello", "NOT", "NEW"])
    #   #=> [1, 6, 7, 8]
    def search(keys, charset = nil)
      return search_internal("SEARCH", keys, charset)
    end

    # Similar to #search, but returns unique identifiers.
    def uid_search(keys, charset = nil)
      return search_internal("UID SEARCH", keys, charset)
    end

    # Sends a FETCH command to retrieve data associated with a message
    # in the mailbox.
    #
    # The +set+ parameter is a number or a range between two numbers,
    # or an array of those.  The number is a message sequence number,
    # where -1 represents a '*' for use in range notation like 100..-1
    # being interpreted as '100:*'.  Beware that the +exclude_end?+
    # property of a Range object is ignored, and the contents of a
    # range are independent of the order of the range endpoints as per
    # the protocol specification, so 1...5, 5..1 and 5...1 are all
    # equivalent to 1..5.
    #
    # +attr+ is a list of attributes to fetch; see the documentation
    # for Net::IMAP::FetchData for a list of valid attributes.
    #
    # The return value is an array of Net::IMAP::FetchData or nil
    # (instead of an empty array) if there is no matching message.
    #
    # For example:
    #
    #   p imap.fetch(6..8, "UID")
    #   #=> [#<Net::IMAP::FetchData seqno=6, attr={"UID"=>98}>, \\
    #        #<Net::IMAP::FetchData seqno=7, attr={"UID"=>99}>, \\
    #        #<Net::IMAP::FetchData seqno=8, attr={"UID"=>100}>]
    #   p imap.fetch(6, "BODY[HEADER.FIELDS (SUBJECT)]")
    #   #=> [#<Net::IMAP::FetchData seqno=6, attr={"BODY[HEADER.FIELDS (SUBJECT)]"=>"Subject: test\r\n\r\n"}>]
    #   data = imap.uid_fetch(98, ["RFC822.SIZE", "INTERNALDATE"])[0]
    #   p data.seqno
    #   #=> 6
    #   p data.attr["RFC822.SIZE"]
    #   #=> 611
    #   p data.attr["INTERNALDATE"]
    #   #=> "12-Oct-2000 22:40:59 +0900"
    #   p data.attr["UID"]
    #   #=> 98
    def fetch(set, attr, mod = nil)
      return fetch_internal("FETCH", set, attr, mod)
    end

    # Similar to #fetch, but +set+ contains unique identifiers.
    def uid_fetch(set, attr, mod = nil)
      return fetch_internal("UID FETCH", set, attr, mod)
    end

    # Sends a STORE command to alter data associated with messages
    # in the mailbox, in particular their flags. The +set+ parameter
    # is a number, an array of numbers, or a Range object. Each number
    # is a message sequence number.  +attr+ is the name of a data item
    # to store: 'FLAGS' will replace the message's flag list
    # with the provided one, '+FLAGS' will add the provided flags,
    # and '-FLAGS' will remove them.  +flags+ is a list of flags.
    #
    # The return value is an array of Net::IMAP::FetchData. For example:
    #
    #   p imap.store(6..8, "+FLAGS", [:Deleted])
    #   #=> [#<Net::IMAP::FetchData seqno=6, attr={"FLAGS"=>[:Seen, :Deleted]}>, \\
    #        #<Net::IMAP::FetchData seqno=7, attr={"FLAGS"=>[:Seen, :Deleted]}>, \\
    #        #<Net::IMAP::FetchData seqno=8, attr={"FLAGS"=>[:Seen, :Deleted]}>]
    def store(set, attr, flags)
      return store_internal("STORE", set, attr, flags)
    end

    # Similar to #store, but +set+ contains unique identifiers.
    def uid_store(set, attr, flags)
      return store_internal("UID STORE", set, attr, flags)
    end

    # Sends a COPY command to copy the specified message(s) to the end
    # of the specified destination +mailbox+. The +set+ parameter is
    # a number, an array of numbers, or a Range object. The number is
    # a message sequence number.
    def copy(set, mailbox)
      copy_internal("COPY", set, mailbox)
    end

    # Similar to #copy, but +set+ contains unique identifiers.
    def uid_copy(set, mailbox)
      copy_internal("UID COPY", set, mailbox)
    end

    # Sends a MOVE command to move the specified message(s) to the end
    # of the specified destination +mailbox+. The +set+ parameter is
    # a number, an array of numbers, or a Range object. The number is
    # a message sequence number.
    #
    # The MOVE extension is described in [EXT-MOVE[https://tools.ietf.org/html/rfc6851]].
    def move(set, mailbox)
      copy_internal("MOVE", set, mailbox)
    end

    # Similar to #move, but +set+ contains unique identifiers.
    #
    # The MOVE extension is described in [EXT-MOVE[https://tools.ietf.org/html/rfc6851]].
    def uid_move(set, mailbox)
      copy_internal("UID MOVE", set, mailbox)
    end

    # Sends a SORT command to sort messages in the mailbox.
    # Returns an array of message sequence numbers. For example:
    #
    #   p imap.sort(["FROM"], ["ALL"], "US-ASCII")
    #   #=> [1, 2, 3, 5, 6, 7, 8, 4, 9]
    #   p imap.sort(["DATE"], ["SUBJECT", "hello"], "US-ASCII")
    #   #=> [6, 7, 8, 1]
    #
    # The SORT extension is described in [EXT-SORT-THREAD[https://tools.ietf.org/html/rfc5256]].
    def sort(sort_keys, search_keys, charset)
      return sort_internal("SORT", sort_keys, search_keys, charset)
    end

    # Similar to #sort, but returns an array of unique identifiers.
    #
    # The SORT extension is described in [EXT-SORT-THREAD[https://tools.ietf.org/html/rfc5256]].
    def uid_sort(sort_keys, search_keys, charset)
      return sort_internal("UID SORT", sort_keys, search_keys, charset)
    end

    # Adds a response handler. For example, to detect when
    # the server sends a new EXISTS response (which normally
    # indicates new messages being added to the mailbox),
    # add the following handler after selecting the
    # mailbox:
    #
    #   imap.add_response_handler { |resp|
    #     if resp.kind_of?(Net::IMAP::UntaggedResponse) and resp.name == "EXISTS"
    #       puts "Mailbox now has #{resp.data} messages"
    #     end
    #   }
    #
    def add_response_handler(handler = nil, &block)
      raise ArgumentError, "two Procs are passed" if handler && block
      @response_handlers.push(block || handler)
    end

    # Removes the response handler.
    def remove_response_handler(handler)
      @response_handlers.delete(handler)
    end

    # Similar to #search, but returns message sequence numbers in threaded
    # format, as a Net::IMAP::ThreadMember tree.  The supported algorithms
    # are:
    #
    # ORDEREDSUBJECT:: split into single-level threads according to subject,
    #                  ordered by date.
    # REFERENCES:: split into threads by parent/child relationships determined
    #              by which message is a reply to which.
    #
    # Unlike #search, +charset+ is a required argument.  US-ASCII
    # and UTF-8 are sample values.
    #
    # The THREAD extension is described in [EXT-SORT-THREAD[https://tools.ietf.org/html/rfc5256]].
    def thread(algorithm, search_keys, charset)
      return thread_internal("THREAD", algorithm, search_keys, charset)
    end

    # Similar to #thread, but returns unique identifiers instead of
    # message sequence numbers.
    #
    # The THREAD extension is described in [EXT-SORT-THREAD[https://tools.ietf.org/html/rfc5256]].
    def uid_thread(algorithm, search_keys, charset)
      return thread_internal("UID THREAD", algorithm, search_keys, charset)
    end

    # Sends an IDLE command that waits for notifications of new or expunged
    # messages.  Yields responses from the server during the IDLE.
    #
    # Use #idle_done to leave IDLE.
    #
    # If +timeout+ is given, this method returns after +timeout+ seconds passed.
    # +timeout+ can be used for keep-alive.  For example, the following code
    # checks the connection for each 60 seconds.
    #
    #   loop do
    #     imap.idle(60) do |res|
    #       ...
    #     end
    #   end
    def idle(timeout = nil, &response_handler)
      raise LocalJumpError, "no block given" unless response_handler

      response = nil

      synchronize do
        tag = Thread.current[:net_imap_tag] = generate_tag
        put_string("#{tag} IDLE#{CRLF}")

        begin
          add_response_handler(&response_handler)
          @idle_done_cond = new_cond
          @idle_done_cond.wait(timeout)
          @idle_done_cond = nil
          if @receiver_thread_terminating
            raise @exception || Net::IMAP::Error.new("connection closed")
          end
        ensure
          unless @receiver_thread_terminating
            remove_response_handler(response_handler)
            put_string("DONE#{CRLF}")
            response = get_tagged_response(tag, "IDLE", @idle_response_timeout)
          end
        end
      end

      return response
    end

    # Leaves IDLE.
    def idle_done
      synchronize do
        if @idle_done_cond.nil?
          raise Net::IMAP::Error, "not during IDLE"
        end
        @idle_done_cond.signal
      end
    end

    private

    CRLF = "\r\n"      # :nodoc:
    PORT = 143         # :nodoc:
    SSL_PORT = 993   # :nodoc:

    @@debug = false

    # :call-seq:
    #    Net::IMAP.new(host, options = {})
    #
    # Creates a new Net::IMAP object and connects it to the specified
    # +host+.
    #
    # +options+ is an option hash, each key of which is a symbol.
    #
    # The available options are:
    #
    # port::  Port number (default value is 143 for imap, or 993 for imaps)
    # ssl::   If +options[:ssl]+ is true, then an attempt will be made
    #         to use SSL (now TLS) to connect to the server.  For this to work
    #         OpenSSL [OSSL] and the Ruby OpenSSL [RSSL] extensions need to
    #         be installed.
    #         If +options[:ssl]+ is a hash, it's passed to
    #         OpenSSL::SSL::SSLContext#set_params as parameters.
    # open_timeout:: Seconds to wait until a connection is opened
    # idle_response_timeout:: Seconds to wait until an IDLE response is received
    #
    # The most common errors are:
    #
    # Errno::ECONNREFUSED:: Connection refused by +host+ or an intervening
    #                       firewall.
    # Errno::ETIMEDOUT:: Connection timed out (possibly due to packets
    #                    being dropped by an intervening firewall).
    # Errno::ENETUNREACH:: There is no route to that network.
    # SocketError:: Hostname not known or other socket error.
    # Net::IMAP::ByeResponseError:: The connected to the host was successful, but
    #                               it immediately said goodbye.
    def initialize(host, port_or_options = {},
                   usessl = false, certs = nil, verify = true)
      super()
      @host = host
      begin
        options = port_or_options.to_hash
      rescue NoMethodError
        # for backward compatibility
        options = {}
        options[:port] = port_or_options
        if usessl
          options[:ssl] = create_ssl_params(certs, verify)
        end
      end
      @port = options[:port] || (options[:ssl] ? SSL_PORT : PORT)
      @tag_prefix = "RUBY"
      @tagno = 0
      @open_timeout = options[:open_timeout] || 30
      @idle_response_timeout = options[:idle_response_timeout] || 5
      @parser = ResponseParser.new
      @sock = tcp_socket(@host, @port)
      begin
        if options[:ssl]
          start_tls_session(options[:ssl])
          @usessl = true
        else
          @usessl = false
        end
        @responses = Hash.new([].freeze)
        @tagged_responses = {}
        @response_handlers = []
        @tagged_response_arrival = new_cond
        @continued_command_tag = nil
        @continuation_request_arrival = new_cond
        @continuation_request_exception = nil
        @idle_done_cond = nil
        @logout_command_tag = nil
        @debug_output_bol = true
        @exception = nil

        @greeting = get_response
        if @greeting.nil?
          raise Error, "connection closed"
        end
        if @greeting.name == "BYE"
          raise ByeResponseError, @greeting
        end

        @client_thread = Thread.current
        @receiver_thread = Thread.start {
          begin
            receive_responses
          rescue Exception
          end
        }
        @receiver_thread_terminating = false
      rescue Exception
        @sock.close
        raise
      end
    end

    def tcp_socket(host, port)
      s = Socket.tcp(host, port, :connect_timeout => @open_timeout)
      s.setsockopt(:SOL_SOCKET, :SO_KEEPALIVE, true)
      s
    rescue Errno::ETIMEDOUT
      raise Net::OpenTimeout, "Timeout to open TCP connection to " +
        "#{host}:#{port} (exceeds #{@open_timeout} seconds)"
    end

    def receive_responses
      connection_closed = false
      until connection_closed
        synchronize do
          @exception = nil
        end
        begin
          resp = get_response
        rescue Exception => e
          synchronize do
            @sock.close
            @exception = e
          end
          break
        end
        unless resp
          synchronize do
            @exception = EOFError.new("end of file reached")
          end
          break
        end
        begin
          synchronize do
            case resp
            when TaggedResponse
              @tagged_responses[resp.tag] = resp
              @tagged_response_arrival.broadcast
              case resp.tag
              when @logout_command_tag
                return
              when @continued_command_tag
                @continuation_request_exception =
                  RESPONSE_ERRORS[resp.name].new(resp)
                @continuation_request_arrival.signal
              end
            when UntaggedResponse
              record_response(resp.name, resp.data)
              if resp.data.instance_of?(ResponseText) &&
                  (code = resp.data.code)
                record_response(code.name, code.data)
              end
              if resp.name == "BYE" && @logout_command_tag.nil?
                @sock.close
                @exception = ByeResponseError.new(resp)
                connection_closed = true
              end
            when ContinuationRequest
              @continuation_request_arrival.signal
            end
            @response_handlers.each do |handler|
              handler.call(resp)
            end
          end
        rescue Exception => e
          @exception = e
          synchronize do
            @tagged_response_arrival.broadcast
            @continuation_request_arrival.broadcast
          end
        end
      end
      synchronize do
        @receiver_thread_terminating = true
        @tagged_response_arrival.broadcast
        @continuation_request_arrival.broadcast
        if @idle_done_cond
          @idle_done_cond.signal
        end
      end
    end

    def get_tagged_response(tag, cmd, timeout = nil)
      if timeout
        deadline = Time.now + timeout
      end
      until @tagged_responses.key?(tag)
        raise @exception if @exception
        if timeout
          timeout = deadline - Time.now
          if timeout <= 0
            return nil
          end
        end
        @tagged_response_arrival.wait(timeout)
      end
      resp = @tagged_responses.delete(tag)
      case resp.name
      when /\A(?:OK)\z/ni
        return resp
      when /\A(?:NO)\z/ni
        raise NoResponseError, resp
      when /\A(?:BAD)\z/ni
        raise BadResponseError, resp
      else
        raise UnknownResponseError, resp
      end
    end

    def get_response
      buff = String.new
      while true
        s = @sock.gets(CRLF)
        break unless s
        buff.concat(s)
        if /\{(\d+)\}\r\n/n =~ s
          s = @sock.read($1.to_i)
          buff.concat(s)
        else
          break
        end
      end
      return nil if buff.length == 0
      if @@debug
        $stderr.print(buff.gsub(/^/n, "S: "))
      end
      return @parser.parse(buff)
    end

    def record_response(name, data)
      unless @responses.has_key?(name)
        @responses[name] = []
      end
      @responses[name].push(data)
    end

    def send_command(cmd, *args, &block)
      synchronize do
        args.each do |i|
          validate_data(i)
        end
        tag = generate_tag
        put_string(tag + " " + cmd)
        args.each do |i|
          put_string(" ")
          send_data(i, tag)
        end
        put_string(CRLF)
        if cmd == "LOGOUT"
          @logout_command_tag = tag
        end
        if block
          add_response_handler(&block)
        end
        begin
          return get_tagged_response(tag, cmd)
        ensure
          if block
            remove_response_handler(block)
          end
        end
      end
    end

    def generate_tag
      @tagno += 1
      return format("%s%04d", @tag_prefix, @tagno)
    end

    def put_string(str)
      @sock.print(str)
      if @@debug
        if @debug_output_bol
          $stderr.print("C: ")
        end
        $stderr.print(str.gsub(/\n(?!\z)/n, "\nC: "))
        if /\r\n\z/n.match(str)
          @debug_output_bol = true
        else
          @debug_output_bol = false
        end
      end
    end

    def search_internal(cmd, keys, charset)
      if keys.instance_of?(String)
        keys = [RawData.new(keys)]
      else
        normalize_searching_criteria(keys)
      end
      synchronize do
        if charset
          send_command(cmd, "CHARSET", charset, *keys)
        else
          send_command(cmd, *keys)
        end
        return @responses.delete("SEARCH")[-1]
      end
    end

    def fetch_internal(cmd, set, attr, mod = nil)
      case attr
      when String then
        attr = RawData.new(attr)
      when Array then
        attr = attr.map { |arg|
          arg.is_a?(String) ? RawData.new(arg) : arg
        }
      end

      synchronize do
        @responses.delete("FETCH")
        if mod
          send_command(cmd, MessageSet.new(set), attr, mod)
        else
          send_command(cmd, MessageSet.new(set), attr)
        end
        return @responses.delete("FETCH")
      end
    end

    def store_internal(cmd, set, attr, flags)
      if attr.instance_of?(String)
        attr = RawData.new(attr)
      end
      synchronize do
        @responses.delete("FETCH")
        send_command(cmd, MessageSet.new(set), attr, flags)
        return @responses.delete("FETCH")
      end
    end

    def copy_internal(cmd, set, mailbox)
      send_command(cmd, MessageSet.new(set), mailbox)
    end

    def sort_internal(cmd, sort_keys, search_keys, charset)
      if search_keys.instance_of?(String)
        search_keys = [RawData.new(search_keys)]
      else
        normalize_searching_criteria(search_keys)
      end
      normalize_searching_criteria(search_keys)
      synchronize do
        send_command(cmd, sort_keys, charset, *search_keys)
        return @responses.delete("SORT")[-1]
      end
    end

    def thread_internal(cmd, algorithm, search_keys, charset)
      if search_keys.instance_of?(String)
        search_keys = [RawData.new(search_keys)]
      else
        normalize_searching_criteria(search_keys)
      end
      normalize_searching_criteria(search_keys)
      send_command(cmd, algorithm, charset, *search_keys)
      return @responses.delete("THREAD")[-1]
    end

    def normalize_searching_criteria(keys)
      keys.collect! do |i|
        case i
        when -1, Range, Array
          MessageSet.new(i)
        else
          i
        end
      end
    end

    def create_ssl_params(certs = nil, verify = true)
      params = {}
      if certs
        if File.file?(certs)
          params[:ca_file] = certs
        elsif File.directory?(certs)
          params[:ca_path] = certs
        end
      end
      if verify
        params[:verify_mode] = VERIFY_PEER
      else
        params[:verify_mode] = VERIFY_NONE
      end
      return params
    end

    def start_tls_session(params = {})
      unless defined?(OpenSSL::SSL)
        raise "SSL extension not installed"
      end
      if @sock.kind_of?(OpenSSL::SSL::SSLSocket)
        raise RuntimeError, "already using SSL"
      end
      begin
        params = params.to_hash
      rescue NoMethodError
        params = {}
      end
      context = SSLContext.new
      context.set_params(params)
      if defined?(VerifyCallbackProc)
        context.verify_callback = VerifyCallbackProc
      end
      @sock = SSLSocket.new(@sock, context)
      @sock.sync_close = true
      @sock.hostname = @host if @sock.respond_to? :hostname=
      ssl_socket_connect(@sock, @open_timeout)
      if context.verify_mode != VERIFY_NONE
        @sock.post_connection_check(@host)
      end
    end

  end
end

require_relative "imap/errors"
require_relative "imap/command_data"
require_relative "imap/data_encoding"
require_relative "imap/flags"
require_relative "imap/response_data"
require_relative "imap/response_parser"
require_relative "imap/authenticators"
