# frozen_string_literal: true
#
# cgi/session.rb - session support for cgi scripts
#
# Copyright (C) 2001  Yukihiro "Matz" Matsumoto
# Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright (C) 2000  Information-technology Promotion Agency, Japan
#
# Author: Yukihiro "Matz" Matsumoto
#
# Documentation: William Webber (william@williamwebber.com)

require 'cgi'
require 'tmpdir'

class CGI

  # == Overview
  #
  # This file provides the CGI::Session class, which provides session
  # support for CGI scripts.  A session is a sequence of HTTP requests
  # and responses linked together and associated with a single client.
  # Information associated with the session is stored
  # on the server between requests.  A session id is passed between client
  # and server with every request and response, transparently
  # to the user.  This adds state information to the otherwise stateless
  # HTTP request/response protocol.
  #
  # == Lifecycle
  #
  # A CGI::Session instance is created from a CGI object.  By default,
  # this CGI::Session instance will start a new session if none currently
  # exists, or continue the current session for this client if one does
  # exist.  The +new_session+ option can be used to either always or
  # never create a new session.  See #new() for more details.
  #
  # #delete() deletes a session from session storage.  It
  # does not however remove the session id from the client.  If the client
  # makes another request with the same id, the effect will be to start
  # a new session with the old session's id.
  #
  # == Setting and retrieving session data.
  #
  # The Session class associates data with a session as key-value pairs.
  # This data can be set and retrieved by indexing the Session instance
  # using '[]', much the same as hashes (although other hash methods
  # are not supported).
  #
  # When session processing has been completed for a request, the
  # session should be closed using the close() method.  This will
  # store the session's state to persistent storage.  If you want
  # to store the session's state to persistent storage without
  # finishing session processing for this request, call the update()
  # method.
  #
  # == Storing session state
  #
  # The caller can specify what form of storage to use for the session's
  # data with the +database_manager+ option to CGI::Session::new.  The
  # following storage classes are provided as part of the standard library:
  #
  # CGI::Session::FileStore:: stores data as plain text in a flat file.  Only
  #                           works with String data.  This is the default
  #                           storage type.
  # CGI::Session::MemoryStore:: stores data in an in-memory hash.  The data
  #                             only persists for as long as the current Ruby
  #                             interpreter instance does.
  # CGI::Session::PStore:: stores data in Marshalled format.  Provided by
  #                        cgi/session/pstore.rb.  Supports data of any type,
  #                        and provides file-locking and transaction support.
  #
  # Custom storage types can also be created by defining a class with
  # the following methods:
  #
  #    new(session, options)
  #    restore  # returns hash of session data.
  #    update
  #    close
  #    delete
  #
  # Changing storage type mid-session does not work.  Note in particular
  # that by default the FileStore and PStore session data files have the
  # same name.  If your application switches from one to the other without
  # making sure that filenames will be different
  # and clients still have old sessions lying around in cookies, then
  # things will break nastily!
  #
  # == Maintaining the session id.
  #
  # Most session state is maintained on the server.  However, a session
  # id must be passed backwards and forwards between client and server
  # to maintain a reference to this session state.
  #
  # The simplest way to do this is via cookies.  The CGI::Session class
  # provides transparent support for session id communication via cookies
  # if the client has cookies enabled.
  #
  # If the client has cookies disabled, the session id must be included
  # as a parameter of all requests sent by the client to the server.  The
  # CGI::Session class in conjunction with the CGI class will transparently
  # add the session id as a hidden input field to all forms generated
  # using the CGI#form() HTML generation method.  No built-in support is
  # provided for other mechanisms, such as URL re-writing.  The caller is
  # responsible for extracting the session id from the session_id
  # attribute and manually encoding it in URLs and adding it as a hidden
  # input to HTML forms created by other mechanisms.  Also, session expiry
  # is not automatically handled.
  #
  # == Examples of use
  #
  # === Setting the user's name
  #
  #   require 'cgi'
  #   require 'cgi/session'
  #   require 'cgi/session/pstore'     # provides CGI::Session::PStore
  #
  #   cgi = CGI.new("html4")
  #
  #   session = CGI::Session.new(cgi,
  #       'database_manager' => CGI::Session::PStore,  # use PStore
  #       'session_key' => '_rb_sess_id',              # custom session key
  #       'session_expires' => Time.now + 30 * 60,     # 30 minute timeout
  #       'prefix' => 'pstore_sid_')                   # PStore option
  #   if cgi.has_key?('user_name') and cgi['user_name'] != ''
  #       # coerce to String: cgi[] returns the
  #       # string-like CGI::QueryExtension::Value
  #       session['user_name'] = cgi['user_name'].to_s
  #   elsif !session['user_name']
  #       session['user_name'] = "guest"
  #   end
  #   session.close
  #
  # === Creating a new session safely
  #
  #   require 'cgi'
  #   require 'cgi/session'
  #
  #   cgi = CGI.new("html4")
  #
  #   # We make sure to delete an old session if one exists,
  #   # not just to free resources, but to prevent the session
  #   # from being maliciously hijacked later on.
  #   begin
  #       session = CGI::Session.new(cgi, 'new_session' => false)
  #       session.delete
  #   rescue ArgumentError  # if no old session
  #   end
  #   session = CGI::Session.new(cgi, 'new_session' => true)
  #   session.close
  #
  class Session

    class NoSession < RuntimeError #:nodoc:
    end

    # The id of this session.
    attr_reader :session_id, :new_session

    def Session::callback(dbman)  #:nodoc:
      Proc.new{
        dbman[0].close unless dbman.empty?
      }
    end

    # Create a new session id.
    #
    # The session id is a secure random number by SecureRandom
    # if possible, otherwise an SHA512 hash based upon the time,
    # a random number, and a constant string.  This routine is
    # used internally for automatically generated session ids.
    def create_new_id
      require 'securerandom'
      begin
        # by OpenSSL, or system provided entropy pool
        session_id = SecureRandom.hex(16)
      rescue NotImplementedError
        # never happens on modern systems
        require 'digest'
        d = Digest('SHA512').new
        now = Time::now
        d.update(now.to_s)
        d.update(String(now.usec))
        d.update(String(rand(0)))
        d.update(String($$))
        d.update('foobar')
        session_id = d.hexdigest[0, 32]
      end
      session_id
    end
    private :create_new_id


    # Create a new file to store the session data.
    #
    # This file will be created if it does not exist, or opened if it
    # does.
    #
    # This path is generated under _tmpdir_ from _prefix_, the
    # digested session id, and _suffix_.
    #
    # +option+ is a hash of options for the initializer.  The
    # following options are recognised:
    #
    # tmpdir:: the directory to use for storing the FileStore
    #          file.  Defaults to Dir::tmpdir (generally "/tmp"
    #          on Unix systems).
    # prefix:: the prefix to add to the session id when generating
    #          the filename for this session's FileStore file.
    #          Defaults to "cgi_sid_".
    # suffix:: the prefix to add to the session id when generating
    #          the filename for this session's FileStore file.
    #          Defaults to the empty string.
    def new_store_file(option={}) # :nodoc:
      dir = option['tmpdir'] || Dir::tmpdir
      prefix = option['prefix']
      suffix = option['suffix']
      require 'digest/md5'
      md5 = Digest::MD5.hexdigest(session_id)[0,16]
      path = dir+"/"
      path << prefix if prefix
      path << md5
      path << suffix if suffix
      if File::exist? path
        hash = nil
      elsif new_session
        hash = {}
      else
        raise NoSession, "uninitialized session"
      end
      return path, hash
    end

    # Create a new CGI::Session object for +request+.
    #
    # +request+ is an instance of the +CGI+ class (see cgi.rb).
    # +option+ is a hash of options for initialising this
    # CGI::Session instance.  The following options are
    # recognised:
    #
    # session_key:: the parameter name used for the session id.
    #               Defaults to '_session_id'.
    # session_id:: the session id to use.  If not provided, then
    #              it is retrieved from the +session_key+ parameter
    #              of the request, or automatically generated for
    #              a new session.
    # new_session:: if true, force creation of a new session.  If not set,
    #               a new session is only created if none currently
    #               exists.  If false, a new session is never created,
    #               and if none currently exists and the +session_id+
    #               option is not set, an ArgumentError is raised.
    # database_manager:: the name of the class providing storage facilities
    #                    for session state persistence.  Built-in support
    #                    is provided for +FileStore+ (the default),
    #                    +MemoryStore+, and +PStore+ (from
    #                    cgi/session/pstore.rb).  See the documentation for
    #                    these classes for more details.
    #
    # The following options are also recognised, but only apply if the
    # session id is stored in a cookie.
    #
    # session_expires:: the time the current session expires, as a
    #                   +Time+ object.  If not set, the session will terminate
    #                   when the user's browser is closed.
    # session_domain:: the hostname domain for which this session is valid.
    #                  If not set, defaults to the hostname of the server.
    # session_secure:: if +true+, this session will only work over HTTPS.
    # session_path:: the path for which this session applies.  Defaults
    #                to the directory of the CGI script.
    #
    # +option+ is also passed on to the session storage class initializer; see
    # the documentation for each session storage class for the options
    # they support.
    #
    # The retrieved or created session is automatically added to +request+
    # as a cookie, and also to its +output_hidden+ table, which is used
    # to add hidden input elements to forms.
    #
    # *WARNING* the +output_hidden+
    # fields are surrounded by a <fieldset> tag in HTML 4 generation, which
    # is _not_ invisible on many browsers; you may wish to disable the
    # use of fieldsets with code similar to the following
    # (see https://blade.ruby-lang.org/ruby-list/37805)
    #
    #   cgi = CGI.new("html4")
    #   class << cgi
    #       undef_method :fieldset
    #   end
    #
    def initialize(request, option={})
      @new_session = false
      session_key = option['session_key'] || '_session_id'
      session_id = option['session_id']
      unless session_id
        if option['new_session']
          session_id = create_new_id
          @new_session = true
        end
      end
      unless session_id
        if request.key?(session_key)
          session_id = request[session_key]
          session_id = session_id.read if session_id.respond_to?(:read)
        end
        unless session_id
          session_id, = request.cookies[session_key]
        end
        unless session_id
          unless option.fetch('new_session', true)
            raise ArgumentError, "session_key `%s' should be supplied"%session_key
          end
          session_id = create_new_id
          @new_session = true
        end
      end
      @session_id = session_id
      dbman = option['database_manager'] || FileStore
      begin
        @dbman = dbman::new(self, option)
      rescue NoSession
        unless option.fetch('new_session', true)
          raise ArgumentError, "invalid session_id `%s'"%session_id
        end
        session_id = @session_id = create_new_id unless session_id
        @new_session=true
        retry
      end
      request.instance_eval do
        @output_hidden = {session_key => session_id} unless option['no_hidden']
        @output_cookies =  [
          Cookie::new("name" => session_key,
          "value" => session_id,
          "expires" => option['session_expires'],
          "domain" => option['session_domain'],
          "secure" => option['session_secure'],
          "path" =>
          if option['session_path']
            option['session_path']
          elsif ENV["SCRIPT_NAME"]
            File::dirname(ENV["SCRIPT_NAME"])
          else
          ""
          end)
        ] unless option['no_cookies']
      end
      @dbprot = [@dbman]
      ObjectSpace::define_finalizer(self, Session::callback(@dbprot))
    end

    # Retrieve the session data for key +key+.
    def [](key)
      @data ||= @dbman.restore
      @data[key]
    end

    # Set the session data for key +key+.
    def []=(key, val)
      @write_lock ||= true
      @data ||= @dbman.restore
      @data[key] = val
    end

    # Store session data on the server.  For some session storage types,
    # this is a no-op.
    def update
      @dbman.update
    end

    # Store session data on the server and close the session storage.
    # For some session storage types, this is a no-op.
    def close
      @dbman.close
      @dbprot.clear
    end

    # Delete the session from storage.  Also closes the storage.
    #
    # Note that the session's data is _not_ automatically deleted
    # upon the session expiring.
    def delete
      @dbman.delete
      @dbprot.clear
    end

    # File-based session storage class.
    #
    # Implements session storage as a flat file of 'key=value' values.
    # This storage type only works directly with String values; the
    # user is responsible for converting other types to Strings when
    # storing and from Strings when retrieving.
    class FileStore
      # Create a new FileStore instance.
      #
      # This constructor is used internally by CGI::Session.  The
      # user does not generally need to call it directly.
      #
      # +session+ is the session for which this instance is being
      # created.  The session id must only contain alphanumeric
      # characters; automatically generated session ids observe
      # this requirement.
      #
      # +option+ is a hash of options for the initializer.  The
      # following options are recognised:
      #
      # tmpdir:: the directory to use for storing the FileStore
      #          file.  Defaults to Dir::tmpdir (generally "/tmp"
      #          on Unix systems).
      # prefix:: the prefix to add to the session id when generating
      #          the filename for this session's FileStore file.
      #          Defaults to "cgi_sid_".
      # suffix:: the prefix to add to the session id when generating
      #          the filename for this session's FileStore file.
      #          Defaults to the empty string.
      #
      # This session's FileStore file will be created if it does
      # not exist, or opened if it does.
      def initialize(session, option={})
        option = {'prefix' => 'cgi_sid_'}.update(option)
        @path, @hash = session.new_store_file(option)
      end

      # Restore session state from the session's FileStore file.
      #
      # Returns the session state as a hash.
      def restore
        unless @hash
          @hash = {}
          begin
            lockf = File.open(@path+".lock", "r")
            lockf.flock File::LOCK_SH
            f = File.open(@path, 'r')
            for line in f
              line.chomp!
              k, v = line.split('=',2)
              @hash[CGI.unescape(k)] = Marshal.restore(CGI.unescape(v))
            end
          ensure
            f&.close
            lockf&.close
          end
        end
        @hash
      end

      # Save session state to the session's FileStore file.
      def update
        return unless @hash
        begin
          lockf = File.open(@path+".lock", File::CREAT|File::RDWR, 0600)
          lockf.flock File::LOCK_EX
          f = File.open(@path+".new", File::CREAT|File::TRUNC|File::WRONLY, 0600)
          for k,v in @hash
            f.printf "%s=%s\n", CGI.escape(k), CGI.escape(String(Marshal.dump(v)))
          end
          f.close
          File.rename @path+".new", @path
        ensure
          f&.close
          lockf&.close
        end
      end

      # Update and close the session's FileStore file.
      def close
        update
      end

      # Close and delete the session's FileStore file.
      def delete
        File::unlink @path+".lock" rescue nil
        File::unlink @path+".new" rescue nil
        File::unlink @path rescue nil
      end
    end

    # In-memory session storage class.
    #
    # Implements session storage as a global in-memory hash.  Session
    # data will only persist for as long as the Ruby interpreter
    # instance does.
    class MemoryStore
      GLOBAL_HASH_TABLE = {} #:nodoc:

      # Create a new MemoryStore instance.
      #
      # +session+ is the session this instance is associated with.
      # +option+ is a list of initialisation options.  None are
      # currently recognized.
      def initialize(session, option=nil)
        @session_id = session.session_id
        unless GLOBAL_HASH_TABLE.key?(@session_id)
          unless session.new_session
            raise CGI::Session::NoSession, "uninitialized session"
          end
          GLOBAL_HASH_TABLE[@session_id] = {}
        end
      end

      # Restore session state.
      #
      # Returns session data as a hash.
      def restore
        GLOBAL_HASH_TABLE[@session_id]
      end

      # Update session state.
      #
      # A no-op.
      def update
        # don't need to update; hash is shared
      end

      # Close session storage.
      #
      # A no-op.
      def close
        # don't need to close
      end

      # Delete the session state.
      def delete
        GLOBAL_HASH_TABLE.delete(@session_id)
      end
    end

    # Dummy session storage class.
    #
    # Implements session storage place holder.  No actual storage
    # will be done.
    class NullStore
      # Create a new NullStore instance.
      #
      # +session+ is the session this instance is associated with.
      # +option+ is a list of initialisation options.  None are
      # currently recognised.
      def initialize(session, option=nil)
      end

      # Restore (empty) session state.
      def restore
        {}
      end

      # Update session state.
      #
      # A no-op.
      def update
      end

      # Close session storage.
      #
      # A no-op.
      def close
      end

      # Delete the session state.
      #
      # A no-op.
      def delete
      end
    end
  end
end
