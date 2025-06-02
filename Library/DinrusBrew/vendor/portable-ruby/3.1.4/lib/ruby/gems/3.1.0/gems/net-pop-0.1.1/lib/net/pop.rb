# frozen_string_literal: true
# = net/pop.rb
#
# Copyright (c) 1999-2007 Yukihiro Matsumoto.
#
# Copyright (c) 1999-2007 Minero Aoki.
#
# Written & maintained by Minero Aoki <aamine@loveruby.net>.
#
# Documented by William Webber and Minero Aoki.
#
# This program is free software. You can re-distribute and/or
# modify this program under the same terms as Ruby itself,
# Ruby Distribute License.
#
# NOTE: You can find Japanese version of this document at:
# http://docs.ruby-lang.org/ja/latest/library/net=2fpop.html
#
#   $Id$
#
# See Net::POP3 for documentation.
#

require 'net/protocol'
require 'digest/md5'
require 'timeout'

begin
  require "openssl"
rescue LoadError
end

module Net

  # Non-authentication POP3 protocol error
  # (reply code "-ERR", except authentication).
  class POPError < ProtocolError; end

  # POP3 authentication error.
  class POPAuthenticationError < ProtoAuthError; end

  # Unexpected response from the server.
  class POPBadResponse < POPError; end

  #
  # == What is This Library?
  #
  # This library provides functionality for retrieving
  # email via POP3, the Post Office Protocol version 3. For details
  # of POP3, see [RFC1939] (http://www.ietf.org/rfc/rfc1939.txt).
  #
  # == Examples
  #
  # === Retrieving Messages
  #
  # This example retrieves messages from the server and deletes them
  # on the server.
  #
  # Messages are written to files named 'inbox/1', 'inbox/2', ....
  # Replace 'pop.example.com' with your POP3 server address, and
  # 'YourAccount' and 'YourPassword' with the appropriate account
  # details.
  #
  #     require 'net/pop'
  #
  #     pop = Net::POP3.new('pop.example.com')
  #     pop.start('YourAccount', 'YourPassword')             # (1)
  #     if pop.mails.empty?
  #       puts 'No mail.'
  #     else
  #       i = 0
  #       pop.each_mail do |m|   # or "pop.mails.each ..."   # (2)
  #         File.open("inbox/#{i}", 'w') do |f|
  #           f.write m.pop
  #         end
  #         m.delete
  #         i += 1
  #       end
  #       puts "#{pop.mails.size} mails popped."
  #     end
  #     pop.finish                                           # (3)
  #
  # 1. Call Net::POP3#start and start POP session.
  # 2. Access messages by using POP3#each_mail and/or POP3#mails.
  # 3. Close POP session by calling POP3#finish or use the block form of #start.
  #
  # === Shortened Code
  #
  # The example above is very verbose. You can shorten the code by using
  # some utility methods. First, the block form of Net::POP3.start can
  # be used instead of POP3.new, POP3#start and POP3#finish.
  #
  #     require 'net/pop'
  #
  #     Net::POP3.start('pop.example.com', 110,
  #                     'YourAccount', 'YourPassword') do |pop|
  #       if pop.mails.empty?
  #         puts 'No mail.'
  #       else
  #         i = 0
  #         pop.each_mail do |m|   # or "pop.mails.each ..."
  #           File.open("inbox/#{i}", 'w') do |f|
  #             f.write m.pop
  #           end
  #           m.delete
  #           i += 1
  #         end
  #         puts "#{pop.mails.size} mails popped."
  #       end
  #     end
  #
  # POP3#delete_all is an alternative for #each_mail and #delete.
  #
  #     require 'net/pop'
  #
  #     Net::POP3.start('pop.example.com', 110,
  #                     'YourAccount', 'YourPassword') do |pop|
  #       if pop.mails.empty?
  #         puts 'No mail.'
  #       else
  #         i = 1
  #         pop.delete_all do |m|
  #           File.open("inbox/#{i}", 'w') do |f|
  #             f.write m.pop
  #           end
  #           i += 1
  #         end
  #       end
  #     end
  #
  # And here is an even shorter example.
  #
  #     require 'net/pop'
  #
  #     i = 0
  #     Net::POP3.delete_all('pop.example.com', 110,
  #                          'YourAccount', 'YourPassword') do |m|
  #       File.open("inbox/#{i}", 'w') do |f|
  #         f.write m.pop
  #       end
  #       i += 1
  #     end
  #
  # === Memory Space Issues
  #
  # All the examples above get each message as one big string.
  # This example avoids this.
  #
  #     require 'net/pop'
  #
  #     i = 1
  #     Net::POP3.delete_all('pop.example.com', 110,
  #                          'YourAccount', 'YourPassword') do |m|
  #       File.open("inbox/#{i}", 'w') do |f|
  #         m.pop do |chunk|    # get a message little by little.
  #           f.write chunk
  #         end
  #         i += 1
  #       end
  #     end
  #
  # === Using APOP
  #
  # The net/pop library supports APOP authentication.
  # To use APOP, use the Net::APOP class instead of the Net::POP3 class.
  # You can use the utility method, Net::POP3.APOP(). For example:
  #
  #     require 'net/pop'
  #
  #     # Use APOP authentication if $isapop == true
  #     pop = Net::POP3.APOP($isapop).new('apop.example.com', 110)
  #     pop.start('YourAccount', 'YourPassword') do |pop|
  #       # Rest of the code is the same.
  #     end
  #
  # === Fetch Only Selected Mail Using 'UIDL' POP Command
  #
  # If your POP server provides UIDL functionality,
  # you can grab only selected mails from the POP server.
  # e.g.
  #
  #     def need_pop?( id )
  #       # determine if we need pop this mail...
  #     end
  #
  #     Net::POP3.start('pop.example.com', 110,
  #                     'Your account', 'Your password') do |pop|
  #       pop.mails.select { |m| need_pop?(m.unique_id) }.each do |m|
  #         do_something(m.pop)
  #       end
  #     end
  #
  # The POPMail#unique_id() method returns the unique-id of the message as a
  # String. Normally the unique-id is a hash of the message.
  #
  class POP3 < Protocol
    # version of this library
    VERSION = "0.1.1"

    #
    # Class Parameters
    #

    # returns the port for POP3
    def POP3.default_port
      default_pop3_port()
    end

    # The default port for POP3 connections, port 110
    def POP3.default_pop3_port
      110
    end

    # The default port for POP3S connections, port 995
    def POP3.default_pop3s_port
      995
    end

    def POP3.socket_type   #:nodoc: obsolete
      Net::InternetMessageIO
    end

    #
    # Utilities
    #

    # Returns the APOP class if +isapop+ is true; otherwise, returns
    # the POP class.  For example:
    #
    #     # Example 1
    #     pop = Net::POP3::APOP($is_apop).new(addr, port)
    #
    #     # Example 2
    #     Net::POP3::APOP($is_apop).start(addr, port) do |pop|
    #       ....
    #     end
    #
    def POP3.APOP(isapop)
      isapop ? APOP : POP3
    end

    # Starts a POP3 session and iterates over each POPMail object,
    # yielding it to the +block+.
    # This method is equivalent to:
    #
    #     Net::POP3.start(address, port, account, password) do |pop|
    #       pop.each_mail do |m|
    #         yield m
    #       end
    #     end
    #
    # This method raises a POPAuthenticationError if authentication fails.
    #
    # === Example
    #
    #     Net::POP3.foreach('pop.example.com', 110,
    #                       'YourAccount', 'YourPassword') do |m|
    #       file.write m.pop
    #       m.delete if $DELETE
    #     end
    #
    def POP3.foreach(address, port = nil,
                     account = nil, password = nil,
                     isapop = false, &block)  # :yields: message
      start(address, port, account, password, isapop) {|pop|
        pop.each_mail(&block)
      }
    end

    # Starts a POP3 session and deletes all messages on the server.
    # If a block is given, each POPMail object is yielded to it before
    # being deleted.
    #
    # This method raises a POPAuthenticationError if authentication fails.
    #
    # === Example
    #
    #     Net::POP3.delete_all('pop.example.com', 110,
    #                          'YourAccount', 'YourPassword') do |m|
    #       file.write m.pop
    #     end
    #
    def POP3.delete_all(address, port = nil,
                        account = nil, password = nil,
                        isapop = false, &block)
      start(address, port, account, password, isapop) {|pop|
        pop.delete_all(&block)
      }
    end

    # Opens a POP3 session, attempts authentication, and quits.
    #
    # This method raises POPAuthenticationError if authentication fails.
    #
    # === Example: normal POP3
    #
    #     Net::POP3.auth_only('pop.example.com', 110,
    #                         'YourAccount', 'YourPassword')
    #
    # === Example: APOP
    #
    #     Net::POP3.auth_only('pop.example.com', 110,
    #                         'YourAccount', 'YourPassword', true)
    #
    def POP3.auth_only(address, port = nil,
                       account = nil, password = nil,
                       isapop = false)
      new(address, port, isapop).auth_only account, password
    end

    # Starts a pop3 session, attempts authentication, and quits.
    # This method must not be called while POP3 session is opened.
    # This method raises POPAuthenticationError if authentication fails.
    def auth_only(account, password)
      raise IOError, 'opening previously opened POP session' if started?
      start(account, password) {
        ;
      }
    end

    #
    # SSL
    #

    @ssl_params = nil

    # :call-seq:
    #    Net::POP.enable_ssl(params = {})
    #
    # Enable SSL for all new instances.
    # +params+ is passed to OpenSSL::SSLContext#set_params.
    def POP3.enable_ssl(*args)
      @ssl_params = create_ssl_params(*args)
    end

    # Constructs proper parameters from arguments
    def POP3.create_ssl_params(verify_or_params = {}, certs = nil)
      begin
        params = verify_or_params.to_hash
      rescue NoMethodError
        params = {}
        params[:verify_mode] = verify_or_params
        if certs
          if File.file?(certs)
            params[:ca_file] = certs
          elsif File.directory?(certs)
            params[:ca_path] = certs
          end
        end
      end
      return params
    end

    # Disable SSL for all new instances.
    def POP3.disable_ssl
      @ssl_params = nil
    end

    # returns the SSL Parameters
    #
    # see also POP3.enable_ssl
    def POP3.ssl_params
      return @ssl_params
    end

    # returns +true+ if POP3.ssl_params is set
    def POP3.use_ssl?
      return !@ssl_params.nil?
    end

    # returns whether verify_mode is enable from POP3.ssl_params
    def POP3.verify
      return @ssl_params[:verify_mode]
    end

    # returns the :ca_file or :ca_path from POP3.ssl_params
    def POP3.certs
      return @ssl_params[:ca_file] || @ssl_params[:ca_path]
    end

    #
    # Session management
    #

    # Creates a new POP3 object and open the connection.  Equivalent to
    #
    #   Net::POP3.new(address, port, isapop).start(account, password)
    #
    # If +block+ is provided, yields the newly-opened POP3 object to it,
    # and automatically closes it at the end of the session.
    #
    # === Example
    #
    #    Net::POP3.start(addr, port, account, password) do |pop|
    #      pop.each_mail do |m|
    #        file.write m.pop
    #        m.delete
    #      end
    #    end
    #
    def POP3.start(address, port = nil,
                   account = nil, password = nil,
                   isapop = false, &block)   # :yield: pop
      new(address, port, isapop).start(account, password, &block)
    end

    # Creates a new POP3 object.
    #
    # +address+ is the hostname or ip address of your POP3 server.
    #
    # The optional +port+ is the port to connect to.
    #
    # The optional +isapop+ specifies whether this connection is going
    # to use APOP authentication; it defaults to +false+.
    #
    # This method does *not* open the TCP connection.
    def initialize(addr, port = nil, isapop = false)
      @address = addr
      @ssl_params = POP3.ssl_params
      @port = port
      @apop = isapop

      @command = nil
      @socket = nil
      @started = false
      @open_timeout = 30
      @read_timeout = 60
      @debug_output = nil

      @mails = nil
      @n_mails = nil
      @n_bytes = nil
    end

    # Does this instance use APOP authentication?
    def apop?
      @apop
    end

    # does this instance use SSL?
    def use_ssl?
      return !@ssl_params.nil?
    end

    # :call-seq:
    #    Net::POP#enable_ssl(params = {})
    #
    # Enables SSL for this instance.  Must be called before the connection is
    # established to have any effect.
    # +params[:port]+ is port to establish the SSL connection on; Defaults to 995.
    # +params+ (except :port) is passed to OpenSSL::SSLContext#set_params.
    def enable_ssl(verify_or_params = {}, certs = nil, port = nil)
      begin
        @ssl_params = verify_or_params.to_hash.dup
        @port = @ssl_params.delete(:port) || @port
      rescue NoMethodError
        @ssl_params = POP3.create_ssl_params(verify_or_params, certs)
        @port = port || @port
      end
    end

    # Disable SSL for all new instances.
    def disable_ssl
      @ssl_params = nil
    end

    # Provide human-readable stringification of class state.
    def inspect
      +"#<#{self.class} #{@address}:#{@port} open=#{@started}>"
    end

    # *WARNING*: This method causes a serious security hole.
    # Use this method only for debugging.
    #
    # Set an output stream for debugging.
    #
    # === Example
    #
    #   pop = Net::POP.new(addr, port)
    #   pop.set_debug_output $stderr
    #   pop.start(account, passwd) do |pop|
    #     ....
    #   end
    #
    def set_debug_output(arg)
      @debug_output = arg
    end

    # The address to connect to.
    attr_reader :address

    # The port number to connect to.
    def port
      return @port || (use_ssl? ? POP3.default_pop3s_port : POP3.default_pop3_port)
    end

    # Seconds to wait until a connection is opened.
    # If the POP3 object cannot open a connection within this time,
    # it raises a Net::OpenTimeout exception. The default value is 30 seconds.
    attr_accessor :open_timeout

    # Seconds to wait until reading one block (by one read(1) call).
    # If the POP3 object cannot complete a read() within this time,
    # it raises a Net::ReadTimeout exception. The default value is 60 seconds.
    attr_reader :read_timeout

    # Set the read timeout.
    def read_timeout=(sec)
      @command.socket.read_timeout = sec if @command
      @read_timeout = sec
    end

    # +true+ if the POP3 session has started.
    def started?
      @started
    end

    alias active? started?   #:nodoc: obsolete

    # Starts a POP3 session.
    #
    # When called with block, gives a POP3 object to the block and
    # closes the session after block call finishes.
    #
    # This method raises a POPAuthenticationError if authentication fails.
    def start(account, password) # :yield: pop
      raise IOError, 'POP session already started' if @started
      if block_given?
        begin
          do_start account, password
          return yield(self)
        ensure
          do_finish
        end
      else
        do_start account, password
        return self
      end
    end

    # internal method for Net::POP3.start
    def do_start(account, password) # :nodoc:
      s = Timeout.timeout(@open_timeout, Net::OpenTimeout) do
        TCPSocket.open(@address, port)
      end
      if use_ssl?
        raise 'openssl library not installed' unless defined?(OpenSSL)
        context = OpenSSL::SSL::SSLContext.new
        context.set_params(@ssl_params)
        s = OpenSSL::SSL::SSLSocket.new(s, context)
        s.hostname = @address
        s.sync_close = true
        ssl_socket_connect(s, @open_timeout)
        if context.verify_mode != OpenSSL::SSL::VERIFY_NONE
          s.post_connection_check(@address)
        end
      end
      @socket = InternetMessageIO.new(s,
                                      read_timeout: @read_timeout,
                                      debug_output: @debug_output)
      logging "POP session started: #{@address}:#{@port} (#{@apop ? 'APOP' : 'POP'})"
      on_connect
      @command = POP3Command.new(@socket)
      if apop?
        @command.apop account, password
      else
        @command.auth account, password
      end
      @started = true
    ensure
      # Authentication failed, clean up connection.
      unless @started
        s.close if s
        @socket = nil
        @command = nil
      end
    end
    private :do_start

    # Does nothing
    def on_connect # :nodoc:
    end
    private :on_connect

    # Finishes a POP3 session and closes TCP connection.
    def finish
      raise IOError, 'POP session not yet started' unless started?
      do_finish
    end

    # nil's out the:
    # - mails
    # - number counter for mails
    # - number counter for bytes
    # - quits the current command, if any
    def do_finish # :nodoc:
      @mails = nil
      @n_mails = nil
      @n_bytes = nil
      @command.quit if @command
    ensure
      @started = false
      @command = nil
      @socket.close if @socket
      @socket = nil
    end
    private :do_finish

    # Returns the current command.
    #
    # Raises IOError if there is no active socket
    def command # :nodoc:
      raise IOError, 'POP session not opened yet' \
                                      if not @socket or @socket.closed?
      @command
    end
    private :command

    #
    # POP protocol wrapper
    #

    # Returns the number of messages on the POP server.
    def n_mails
      return @n_mails if @n_mails
      @n_mails, @n_bytes = command().stat
      @n_mails
    end

    # Returns the total size in bytes of all the messages on the POP server.
    def n_bytes
      return @n_bytes if @n_bytes
      @n_mails, @n_bytes = command().stat
      @n_bytes
    end

    # Returns an array of Net::POPMail objects, representing all the
    # messages on the server.  This array is renewed when the session
    # restarts; otherwise, it is fetched from the server the first time
    # this method is called (directly or indirectly) and cached.
    #
    # This method raises a POPError if an error occurs.
    def mails
      return @mails.dup if @mails
      if n_mails() == 0
        # some popd raises error for LIST on the empty mailbox.
        @mails = []
        return []
      end

      @mails = command().list.map {|num, size|
        POPMail.new(num, size, self, command())
      }
      @mails.dup
    end

    # Yields each message to the passed-in block in turn.
    # Equivalent to:
    #
    #   pop3.mails.each do |popmail|
    #     ....
    #   end
    #
    # This method raises a POPError if an error occurs.
    def each_mail(&block)  # :yield: message
      mails().each(&block)
    end

    alias each each_mail

    # Deletes all messages on the server.
    #
    # If called with a block, yields each message in turn before deleting it.
    #
    # === Example
    #
    #     n = 1
    #     pop.delete_all do |m|
    #       File.open("inbox/#{n}") do |f|
    #         f.write m.pop
    #       end
    #       n += 1
    #     end
    #
    # This method raises a POPError if an error occurs.
    #
    def delete_all # :yield: message
      mails().each do |m|
        yield m if block_given?
        m.delete unless m.deleted?
      end
    end

    # Resets the session.  This clears all "deleted" marks from messages.
    #
    # This method raises a POPError if an error occurs.
    def reset
      command().rset
      mails().each do |m|
        m.instance_eval {
          @deleted = false
        }
      end
    end

    def set_all_uids   #:nodoc: internal use only (called from POPMail#uidl)
      uidl = command().uidl
      @mails.each {|m| m.uid = uidl[m.number] }
    end

    # debugging output for +msg+
    def logging(msg)
      @debug_output << msg + "\n" if @debug_output
    end

  end   # class POP3

  # class aliases
  POP = POP3 # :nodoc:
  POPSession  = POP3 # :nodoc:
  POP3Session = POP3 # :nodoc:

  #
  # This class is equivalent to POP3, except that it uses APOP authentication.
  #
  class APOP < POP3
    # Always returns true.
    def apop?
      true
    end
  end

  # class aliases
  APOPSession = APOP

  #
  # This class represents a message which exists on the POP server.
  # Instances of this class are created by the POP3 class; they should
  # not be directly created by the user.
  #
  class POPMail

    def initialize(num, len, pop, cmd)   #:nodoc:
      @number = num
      @length = len
      @pop = pop
      @command = cmd
      @deleted = false
      @uid = nil
    end

    # The sequence number of the message on the server.
    attr_reader :number

    # The length of the message in octets.
    attr_reader :length
    alias size length

    # Provide human-readable stringification of class state.
    def inspect
      +"#<#{self.class} #{@number}#{@deleted ? ' deleted' : ''}>"
    end

    #
    # This method fetches the message.  If called with a block, the
    # message is yielded to the block one chunk at a time.  If called
    # without a block, the message is returned as a String.  The optional
    # +dest+ argument will be prepended to the returned String; this
    # argument is essentially obsolete.
    #
    # === Example without block
    #
    #     POP3.start('pop.example.com', 110,
    #                'YourAccount', 'YourPassword') do |pop|
    #       n = 1
    #       pop.mails.each do |popmail|
    #         File.open("inbox/#{n}", 'w') do |f|
    #           f.write popmail.pop
    #         end
    #         popmail.delete
    #         n += 1
    #       end
    #     end
    #
    # === Example with block
    #
    #     POP3.start('pop.example.com', 110,
    #                'YourAccount', 'YourPassword') do |pop|
    #       n = 1
    #       pop.mails.each do |popmail|
    #         File.open("inbox/#{n}", 'w') do |f|
    #           popmail.pop do |chunk|            ####
    #             f.write chunk
    #           end
    #         end
    #         n += 1
    #       end
    #     end
    #
    # This method raises a POPError if an error occurs.
    #
    def pop( dest = +'', &block ) # :yield: message_chunk
      if block_given?
        @command.retr(@number, &block)
        nil
      else
        @command.retr(@number) do |chunk|
          dest << chunk
        end
        dest
      end
    end

    alias all pop    #:nodoc: obsolete
    alias mail pop   #:nodoc: obsolete

    # Fetches the message header and +lines+ lines of body.
    #
    # The optional +dest+ argument is obsolete.
    #
    # This method raises a POPError if an error occurs.
    def top(lines, dest = +'')
      @command.top(@number, lines) do |chunk|
        dest << chunk
      end
      dest
    end

    # Fetches the message header.
    #
    # The optional +dest+ argument is obsolete.
    #
    # This method raises a POPError if an error occurs.
    def header(dest = +'')
      top(0, dest)
    end

    # Marks a message for deletion on the server.  Deletion does not
    # actually occur until the end of the session; deletion may be
    # cancelled for _all_ marked messages by calling POP3#reset().
    #
    # This method raises a POPError if an error occurs.
    #
    # === Example
    #
    #     POP3.start('pop.example.com', 110,
    #                'YourAccount', 'YourPassword') do |pop|
    #       n = 1
    #       pop.mails.each do |popmail|
    #         File.open("inbox/#{n}", 'w') do |f|
    #           f.write popmail.pop
    #         end
    #         popmail.delete         ####
    #         n += 1
    #       end
    #     end
    #
    def delete
      @command.dele @number
      @deleted = true
    end

    alias delete! delete    #:nodoc: obsolete

    # True if the mail has been deleted.
    def deleted?
      @deleted
    end

    # Returns the unique-id of the message.
    # Normally the unique-id is a hash string of the message.
    #
    # This method raises a POPError if an error occurs.
    def unique_id
      return @uid if @uid
      @pop.set_all_uids
      @uid
    end

    alias uidl unique_id

    def uid=(uid)   #:nodoc: internal use only
      @uid = uid
    end

  end   # class POPMail


  class POP3Command   #:nodoc: internal use only

    def initialize(sock)
      @socket = sock
      @error_occurred = false
      res = check_response(critical { recv_response() })
      @apop_stamp = res.slice(/<[!-~]+@[!-~]+>/)
    end

    attr_reader :socket

    def inspect
      +"#<#{self.class} socket=#{@socket}>"
    end

    def auth(account, password)
      check_response_auth(critical {
        check_response_auth(get_response('USER %s', account))
        get_response('PASS %s', password)
      })
    end

    def apop(account, password)
      raise POPAuthenticationError, 'not APOP server; cannot login' \
                                                      unless @apop_stamp
      check_response_auth(critical {
        get_response('APOP %s %s',
                     account,
                     Digest::MD5.hexdigest(@apop_stamp + password))
      })
    end

    def list
      critical {
        getok 'LIST'
        list = []
        @socket.each_list_item do |line|
          m = /\A(\d+)[ \t]+(\d+)/.match(line) or
                  raise POPBadResponse, "bad response: #{line}"
          list.push  [m[1].to_i, m[2].to_i]
        end
        return list
      }
    end

    def stat
      res = check_response(critical { get_response('STAT') })
      m = /\A\+OK\s+(\d+)\s+(\d+)/.match(res) or
              raise POPBadResponse, "wrong response format: #{res}"
      [m[1].to_i, m[2].to_i]
    end

    def rset
      check_response(critical { get_response('RSET') })
    end

    def top(num, lines = 0, &block)
      critical {
        getok('TOP %d %d', num, lines)
        @socket.each_message_chunk(&block)
      }
    end

    def retr(num, &block)
      critical {
        getok('RETR %d', num)
        @socket.each_message_chunk(&block)
      }
    end

    def dele(num)
      check_response(critical { get_response('DELE %d', num) })
    end

    def uidl(num = nil)
      if num
        res = check_response(critical { get_response('UIDL %d', num) })
        return res.split(/ /)[1]
      else
        critical {
          getok('UIDL')
          table = {}
          @socket.each_list_item do |line|
            num, uid = line.split(' ')
            table[num.to_i] = uid
          end
          return table
        }
      end
    end

    def quit
      check_response(critical { get_response('QUIT') })
    end

    private

    def getok(fmt, *fargs)
      @socket.writeline sprintf(fmt, *fargs)
      check_response(recv_response())
    end

    def get_response(fmt, *fargs)
      @socket.writeline sprintf(fmt, *fargs)
      recv_response()
    end

    def recv_response
      @socket.readline
    end

    def check_response(res)
      raise POPError, res unless /\A\+OK/i =~ res
      res
    end

    def check_response_auth(res)
      raise POPAuthenticationError, res unless /\A\+OK/i =~ res
      res
    end

    def critical
      return '+OK dummy ok response' if @error_occurred
      begin
        return yield()
      rescue Exception
        @error_occurred = true
        raise
      end
    end

  end   # class POP3Command

end   # module Net
