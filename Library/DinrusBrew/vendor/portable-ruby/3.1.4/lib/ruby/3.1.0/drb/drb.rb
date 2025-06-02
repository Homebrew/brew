# frozen_string_literal: false
#
# = drb/drb.rb
#
# Distributed Ruby: _dRuby_ version 2.0.4
#
# Copyright (c) 1999-2003 Masatoshi SEKI.  You can redistribute it and/or
# modify it under the same terms as Ruby.
#
# Author:: Masatoshi SEKI
#
# Documentation:: William Webber (william@williamwebber.com)
#
# == Overview
#
# dRuby is a distributed object system for Ruby.  It allows an object in one
# Ruby process to invoke methods on an object in another Ruby process on the
# same or a different machine.
#
# The Ruby standard library contains the core classes of the dRuby package.
# However, the full package also includes access control lists and the
# Rinda tuple-space distributed task management system, as well as a
# large number of samples.  The full dRuby package can be downloaded from
# the dRuby home page (see *References*).
#
# For an introduction and examples of usage see the documentation to the
# DRb module.
#
# == References
#
# [http://www2a.biglobe.ne.jp/~seki/ruby/druby.html]
#    The dRuby home page, in Japanese.  Contains the full dRuby package
#    and links to other Japanese-language sources.
#
# [http://www2a.biglobe.ne.jp/~seki/ruby/druby.en.html]
#    The English version of the dRuby home page.
#
# [http://pragprog.com/book/sidruby/the-druby-book]
#    The dRuby Book: Distributed and Parallel Computing with Ruby
#    by Masatoshi Seki and Makoto Inoue
#
# [http://www.ruby-doc.org/docs/ProgrammingRuby/html/ospace.html]
#   The chapter from *Programming* *Ruby* by Dave Thomas and Andy Hunt
#   which discusses dRuby.
#
# [http://www.clio.ne.jp/home/web-i31s/Flotuard/Ruby/PRC2K_seki/dRuby.en.html]
#   Translation of presentation on Ruby by Masatoshi Seki.

require 'socket'
require 'io/wait'
require 'monitor'
require_relative 'eq'

#
# == Overview
#
# dRuby is a distributed object system for Ruby.  It is written in
# pure Ruby and uses its own protocol.  No add-in services are needed
# beyond those provided by the Ruby runtime, such as TCP sockets.  It
# does not rely on or interoperate with other distributed object
# systems such as CORBA, RMI, or .NET.
#
# dRuby allows methods to be called in one Ruby process upon a Ruby
# object located in another Ruby process, even on another machine.
# References to objects can be passed between processes.  Method
# arguments and return values are dumped and loaded in marshalled
# format.  All of this is done transparently to both the caller of the
# remote method and the object that it is called upon.
#
# An object in a remote process is locally represented by a
# DRb::DRbObject instance.  This acts as a sort of proxy for the
# remote object.  Methods called upon this DRbObject instance are
# forwarded to its remote object.  This is arranged dynamically at run
# time.  There are no statically declared interfaces for remote
# objects, such as CORBA's IDL.
#
# dRuby calls made into a process are handled by a DRb::DRbServer
# instance within that process.  This reconstitutes the method call,
# invokes it upon the specified local object, and returns the value to
# the remote caller.  Any object can receive calls over dRuby.  There
# is no need to implement a special interface, or mixin special
# functionality.  Nor, in the general case, does an object need to
# explicitly register itself with a DRbServer in order to receive
# dRuby calls.
#
# One process wishing to make dRuby calls upon another process must
# somehow obtain an initial reference to an object in the remote
# process by some means other than as the return value of a remote
# method call, as there is initially no remote object reference it can
# invoke a method upon.  This is done by attaching to the server by
# URI.  Each DRbServer binds itself to a URI such as
# 'druby://example.com:8787'.  A DRbServer can have an object attached
# to it that acts as the server's *front* *object*.  A DRbObject can
# be explicitly created from the server's URI.  This DRbObject's
# remote object will be the server's front object.  This front object
# can then return references to other Ruby objects in the DRbServer's
# process.
#
# Method calls made over dRuby behave largely the same as normal Ruby
# method calls made within a process.  Method calls with blocks are
# supported, as are raising exceptions.  In addition to a method's
# standard errors, a dRuby call may also raise one of the
# dRuby-specific errors, all of which are subclasses of DRb::DRbError.
#
# Any type of object can be passed as an argument to a dRuby call or
# returned as its return value.  By default, such objects are dumped
# or marshalled at the local end, then loaded or unmarshalled at the
# remote end.  The remote end therefore receives a copy of the local
# object, not a distributed reference to it; methods invoked upon this
# copy are executed entirely in the remote process, not passed on to
# the local original.  This has semantics similar to pass-by-value.
#
# However, if an object cannot be marshalled, a dRuby reference to it
# is passed or returned instead.  This will turn up at the remote end
# as a DRbObject instance.  All methods invoked upon this remote proxy
# are forwarded to the local object, as described in the discussion of
# DRbObjects.  This has semantics similar to the normal Ruby
# pass-by-reference.
#
# The easiest way to signal that we want an otherwise marshallable
# object to be passed or returned as a DRbObject reference, rather
# than marshalled and sent as a copy, is to include the
# DRb::DRbUndumped mixin module.
#
# dRuby supports calling remote methods with blocks.  As blocks (or
# rather the Proc objects that represent them) are not marshallable,
# the block executes in the local, not the remote, context.  Each
# value yielded to the block is passed from the remote object to the
# local block, then the value returned by each block invocation is
# passed back to the remote execution context to be collected, before
# the collected values are finally returned to the local context as
# the return value of the method invocation.
#
# == Examples of usage
#
# For more dRuby samples, see the +samples+ directory in the full
# dRuby distribution.
#
# === dRuby in client/server mode
#
# This illustrates setting up a simple client-server drb
# system.  Run the server and client code in different terminals,
# starting the server code first.
#
# ==== Server code
#
#   require 'drb/drb'
#
#   # The URI for the server to connect to
#   URI="druby://localhost:8787"
#
#   class TimeServer
#
#     def get_current_time
#       return Time.now
#     end
#
#   end
#
#   # The object that handles requests on the server
#   FRONT_OBJECT=TimeServer.new
#
#   DRb.start_service(URI, FRONT_OBJECT)
#   # Wait for the drb server thread to finish before exiting.
#   DRb.thread.join
#
# ==== Client code
#
#   require 'drb/drb'
#
#   # The URI to connect to
#   SERVER_URI="druby://localhost:8787"
#
#   # Start a local DRbServer to handle callbacks.
#   #
#   # Not necessary for this small example, but will be required
#   # as soon as we pass a non-marshallable object as an argument
#   # to a dRuby call.
#   #
#   # Note: this must be called at least once per process to take any effect.
#   # This is particularly important if your application forks.
#   DRb.start_service
#
#   timeserver = DRbObject.new_with_uri(SERVER_URI)
#   puts timeserver.get_current_time
#
# === Remote objects under dRuby
#
# This example illustrates returning a reference to an object
# from a dRuby call.  The Logger instances live in the server
# process.  References to them are returned to the client process,
# where methods can be invoked upon them.  These methods are
# executed in the server process.
#
# ==== Server code
#
#   require 'drb/drb'
#
#   URI="druby://localhost:8787"
#
#   class Logger
#
#       # Make dRuby send Logger instances as dRuby references,
#       # not copies.
#       include DRb::DRbUndumped
#
#       def initialize(n, fname)
#           @name = n
#           @filename = fname
#       end
#
#       def log(message)
#           File.open(@filename, "a") do |f|
#               f.puts("#{Time.now}: #{@name}: #{message}")
#           end
#       end
#
#   end
#
#   # We have a central object for creating and retrieving loggers.
#   # This retains a local reference to all loggers created.  This
#   # is so an existing logger can be looked up by name, but also
#   # to prevent loggers from being garbage collected.  A dRuby
#   # reference to an object is not sufficient to prevent it being
#   # garbage collected!
#   class LoggerFactory
#
#       def initialize(bdir)
#           @basedir = bdir
#           @loggers = {}
#       end
#
#       def get_logger(name)
#           if !@loggers.has_key? name
#               # make the filename safe, then declare it to be so
#               fname = name.gsub(/[.\/\\\:]/, "_")
#               @loggers[name] = Logger.new(name, @basedir + "/" + fname)
#           end
#           return @loggers[name]
#       end
#
#   end
#
#   FRONT_OBJECT=LoggerFactory.new("/tmp/dlog")
#
#   DRb.start_service(URI, FRONT_OBJECT)
#   DRb.thread.join
#
# ==== Client code
#
#   require 'drb/drb'
#
#   SERVER_URI="druby://localhost:8787"
#
#   DRb.start_service
#
#   log_service=DRbObject.new_with_uri(SERVER_URI)
#
#   ["loga", "logb", "logc"].each do |logname|
#
#       logger=log_service.get_logger(logname)
#
#       logger.log("Hello, world!")
#       logger.log("Goodbye, world!")
#       logger.log("=== EOT ===")
#
#   end
#
# == Security
#
# As with all network services, security needs to be considered when
# using dRuby.  By allowing external access to a Ruby object, you are
# not only allowing outside clients to call the methods you have
# defined for that object, but by default to execute arbitrary Ruby
# code on your server.  Consider the following:
#
#    # !!! UNSAFE CODE !!!
#    ro = DRbObject::new_with_uri("druby://your.server.com:8989")
#    class << ro
#      undef :instance_eval  # force call to be passed to remote object
#    end
#    ro.instance_eval("`rm -rf *`")
#
# The dangers posed by instance_eval and friends are such that a
# DRbServer should only be used when clients are trusted.
#
# A DRbServer can be configured with an access control list to
# selectively allow or deny access from specified IP addresses.  The
# main druby distribution provides the ACL class for this purpose.  In
# general, this mechanism should only be used alongside, rather than
# as a replacement for, a good firewall.
#
# == dRuby internals
#
# dRuby is implemented using three main components: a remote method
# call marshaller/unmarshaller; a transport protocol; and an
# ID-to-object mapper.  The latter two can be directly, and the first
# indirectly, replaced, in order to provide different behaviour and
# capabilities.
#
# Marshalling and unmarshalling of remote method calls is performed by
# a DRb::DRbMessage instance.  This uses the Marshal module to dump
# the method call before sending it over the transport layer, then
# reconstitute it at the other end.  There is normally no need to
# replace this component, and no direct way is provided to do so.
# However, it is possible to implement an alternative marshalling
# scheme as part of an implementation of the transport layer.
#
# The transport layer is responsible for opening client and server
# network connections and forwarding dRuby request across them.
# Normally, it uses DRb::DRbMessage internally to manage marshalling
# and unmarshalling.  The transport layer is managed by
# DRb::DRbProtocol.  Multiple protocols can be installed in
# DRbProtocol at the one time; selection between them is determined by
# the scheme of a dRuby URI.  The default transport protocol is
# selected by the scheme 'druby:', and implemented by
# DRb::DRbTCPSocket.  This uses plain TCP/IP sockets for
# communication.  An alternative protocol, using UNIX domain sockets,
# is implemented by DRb::DRbUNIXSocket in the file drb/unix.rb, and
# selected by the scheme 'drbunix:'.  A sample implementation over
# HTTP can be found in the samples accompanying the main dRuby
# distribution.
#
# The ID-to-object mapping component maps dRuby object ids to the
# objects they refer to, and vice versa.  The implementation to use
# can be specified as part of a DRb::DRbServer's configuration.  The
# default implementation is provided by DRb::DRbIdConv.  It uses an
# object's ObjectSpace id as its dRuby id.  This means that the dRuby
# reference to that object only remains meaningful for the lifetime of
# the object's process and the lifetime of the object within that
# process.  A modified implementation is provided by DRb::TimerIdConv
# in the file drb/timeridconv.rb.  This implementation retains a local
# reference to all objects exported over dRuby for a configurable
# period of time (defaulting to ten minutes), to prevent them being
# garbage-collected within this time.  Another sample implementation
# is provided in sample/name.rb in the main dRuby distribution.  This
# allows objects to specify their own id or "name".  A dRuby reference
# can be made persistent across processes by having each process
# register an object using the same dRuby name.
#
module DRb

  # Superclass of all errors raised in the DRb module.
  class DRbError < RuntimeError; end

  # Error raised when an error occurs on the underlying communication
  # protocol.
  class DRbConnError < DRbError; end

  # Class responsible for converting between an object and its id.
  #
  # This, the default implementation, uses an object's local ObjectSpace
  # __id__ as its id.  This means that an object's identification over
  # drb remains valid only while that object instance remains alive
  # within the server runtime.
  #
  # For alternative mechanisms, see DRb::TimerIdConv in drb/timeridconv.rb
  # and DRbNameIdConv in sample/name.rb in the full drb distribution.
  class DRbIdConv

    # Convert an object reference id to an object.
    #
    # This implementation looks up the reference id in the local object
    # space and returns the object it refers to.
    def to_obj(ref)
      ObjectSpace._id2ref(ref)
    end

    # Convert an object into a reference id.
    #
    # This implementation returns the object's __id__ in the local
    # object space.
    def to_id(obj)
      case obj
      when Object
        obj.nil? ? nil : obj.__id__
      when BasicObject
        obj.__id__
      end
    end
  end

  # Mixin module making an object undumpable or unmarshallable.
  #
  # If an object which includes this module is returned by method
  # called over drb, then the object remains in the server space
  # and a reference to the object is returned, rather than the
  # object being marshalled and moved into the client space.
  module DRbUndumped
    def _dump(dummy)  # :nodoc:
      raise TypeError, 'can\'t dump'
    end
  end

  # Error raised by the DRb module when an attempt is made to refer to
  # the context's current drb server but the context does not have one.
  # See #current_server.
  class DRbServerNotFound < DRbError; end

  # Error raised by the DRbProtocol module when it cannot find any
  # protocol implementation support the scheme specified in a URI.
  class DRbBadURI < DRbError; end

  # Error raised by a dRuby protocol when it doesn't support the
  # scheme specified in a URI.  See DRb::DRbProtocol.
  class DRbBadScheme < DRbError; end

  # An exception wrapping a DRb::DRbUnknown object
  class DRbUnknownError < DRbError

    # Create a new DRbUnknownError for the DRb::DRbUnknown object +unknown+
    def initialize(unknown)
      @unknown = unknown
      super(unknown.name)
    end

    # Get the wrapped DRb::DRbUnknown object.
    attr_reader :unknown

    def self._load(s)  # :nodoc:
      Marshal::load(s)
    end

    def _dump(lv) # :nodoc:
      Marshal::dump(@unknown)
    end
  end

  # An exception wrapping an error object
  class DRbRemoteError < DRbError

    # Creates a new remote error that wraps the Exception +error+
    def initialize(error)
      @reason = error.class.to_s
      super("#{error.message} (#{error.class})")
      set_backtrace(error.backtrace)
    end

    # the class of the error, as a string.
    attr_reader :reason
  end

  # Class wrapping a marshalled object whose type is unknown locally.
  #
  # If an object is returned by a method invoked over drb, but the
  # class of the object is unknown in the client namespace, or
  # the object is a constant unknown in the client namespace, then
  # the still-marshalled object is returned wrapped in a DRbUnknown instance.
  #
  # If this object is passed as an argument to a method invoked over
  # drb, then the wrapped object is passed instead.
  #
  # The class or constant name of the object can be read from the
  # +name+ attribute.  The marshalled object is held in the +buf+
  # attribute.
  class DRbUnknown

    # Create a new DRbUnknown object.
    #
    # +buf+ is a string containing a marshalled object that could not
    # be unmarshalled.  +err+ is the error message that was raised
    # when the unmarshalling failed.  It is used to determine the
    # name of the unmarshalled object.
    def initialize(err, buf)
      case err.to_s
      when /uninitialized constant (\S+)/
        @name = $1
      when /undefined class\/module (\S+)/
        @name = $1
      else
        @name = nil
      end
      @buf = buf
    end

    # The name of the unknown thing.
    #
    # Class name for unknown objects; variable name for unknown
    # constants.
    attr_reader :name

    # Buffer contained the marshalled, unknown object.
    attr_reader :buf

    def self._load(s) # :nodoc:
      begin
        Marshal::load(s)
      rescue NameError, ArgumentError
        DRbUnknown.new($!, s)
      end
    end

    def _dump(lv) # :nodoc:
      @buf
    end

    # Attempt to load the wrapped marshalled object again.
    #
    # If the class of the object is now known locally, the object
    # will be unmarshalled and returned.  Otherwise, a new
    # but identical DRbUnknown object will be returned.
    def reload
      self.class._load(@buf)
    end

    # Create a DRbUnknownError exception containing this object.
    def exception
      DRbUnknownError.new(self)
    end
  end

  # An Array wrapper that can be sent to another server via DRb.
  #
  # All entries in the array will be dumped or be references that point to
  # the local server.

  class DRbArray

    # Creates a new DRbArray that either dumps or wraps all the items in the
    # Array +ary+ so they can be loaded by a remote DRb server.

    def initialize(ary)
      @ary = ary.collect { |obj|
        if obj.kind_of? DRbUndumped
          DRbObject.new(obj)
        else
          begin
            Marshal.dump(obj)
            obj
          rescue
            DRbObject.new(obj)
          end
        end
      }
    end

    def self._load(s) # :nodoc:
      Marshal::load(s)
    end

    def _dump(lv) # :nodoc:
      Marshal.dump(@ary)
    end
  end

  # Handler for sending and receiving drb messages.
  #
  # This takes care of the low-level marshalling and unmarshalling
  # of drb requests and responses sent over the wire between server
  # and client.  This relieves the implementor of a new drb
  # protocol layer with having to deal with these details.
  #
  # The user does not have to directly deal with this object in
  # normal use.
  class DRbMessage
    def initialize(config) # :nodoc:
      @load_limit = config[:load_limit]
      @argc_limit = config[:argc_limit]
    end

    def dump(obj, error=false)  # :nodoc:
      case obj
      when DRbUndumped
        obj = make_proxy(obj, error)
      when Object
        # nothing
      else
        obj = make_proxy(obj, error)
      end
      begin
        str = Marshal::dump(obj)
      rescue
        str = Marshal::dump(make_proxy(obj, error))
      end
      [str.size].pack('N') + str
    end

    def load(soc)  # :nodoc:
      begin
        sz = soc.read(4)        # sizeof (N)
      rescue
        raise(DRbConnError, $!.message, $!.backtrace)
      end
      raise(DRbConnError, 'connection closed') if sz.nil?
      raise(DRbConnError, 'premature header') if sz.size < 4
      sz = sz.unpack('N')[0]
      raise(DRbConnError, "too large packet #{sz}") if @load_limit < sz
      begin
        str = soc.read(sz)
      rescue
        raise(DRbConnError, $!.message, $!.backtrace)
      end
      raise(DRbConnError, 'connection closed') if str.nil?
      raise(DRbConnError, 'premature marshal format(can\'t read)') if str.size < sz
      DRb.mutex.synchronize do
        begin
          Marshal::load(str)
        rescue NameError, ArgumentError
          DRbUnknown.new($!, str)
        end
      end
    end

    def send_request(stream, ref, msg_id, arg, b) # :nodoc:
      ary = []
      ary.push(dump(ref.__drbref))
      ary.push(dump(msg_id.id2name))
      ary.push(dump(arg.length))
      arg.each do |e|
        ary.push(dump(e))
      end
      ary.push(dump(b))
      stream.write(ary.join(''))
    rescue
      raise(DRbConnError, $!.message, $!.backtrace)
    end

    def recv_request(stream) # :nodoc:
      ref = load(stream)
      ro = DRb.to_obj(ref)
      msg = load(stream)
      argc = load(stream)
      raise(DRbConnError, "too many arguments") if @argc_limit < argc
      argv = Array.new(argc, nil)
      argc.times do |n|
        argv[n] = load(stream)
      end
      block = load(stream)
      return ro, msg, argv, block
    end

    def send_reply(stream, succ, result)  # :nodoc:
      stream.write(dump(succ) + dump(result, !succ))
    rescue
      raise(DRbConnError, $!.message, $!.backtrace)
    end

    def recv_reply(stream)  # :nodoc:
      succ = load(stream)
      result = load(stream)
      [succ, result]
    end

    private
    def make_proxy(obj, error=false) # :nodoc:
      if error
        DRbRemoteError.new(obj)
      else
        DRbObject.new(obj)
      end
    end
  end

  # Module managing the underlying network protocol(s) used by drb.
  #
  # By default, drb uses the DRbTCPSocket protocol.  Other protocols
  # can be defined.  A protocol must define the following class methods:
  #
  #   [open(uri, config)] Open a client connection to the server at +uri+,
  #                       using configuration +config+.  Return a protocol
  #                       instance for this connection.
  #   [open_server(uri, config)] Open a server listening at +uri+,
  #                              using configuration +config+.  Return a
  #                              protocol instance for this listener.
  #   [uri_option(uri, config)] Take a URI, possibly containing an option
  #                             component (e.g. a trailing '?param=val'),
  #                             and return a [uri, option] tuple.
  #
  # All of these methods should raise a DRbBadScheme error if the URI
  # does not identify the protocol they support (e.g. "druby:" for
  # the standard Ruby protocol).  This is how the DRbProtocol module,
  # given a URI, determines which protocol implementation serves that
  # protocol.
  #
  # The protocol instance returned by #open_server must have the
  # following methods:
  #
  # [accept] Accept a new connection to the server.  Returns a protocol
  #          instance capable of communicating with the client.
  # [close] Close the server connection.
  # [uri] Get the URI for this server.
  #
  # The protocol instance returned by #open must have the following methods:
  #
  # [send_request (ref, msg_id, arg, b)]
  #      Send a request to +ref+ with the given message id and arguments.
  #      This is most easily implemented by calling DRbMessage.send_request,
  #      providing a stream that sits on top of the current protocol.
  # [recv_reply]
  #      Receive a reply from the server and return it as a [success-boolean,
  #      reply-value] pair.  This is most easily implemented by calling
  #      DRb.recv_reply, providing a stream that sits on top of the
  #      current protocol.
  # [alive?]
  #      Is this connection still alive?
  # [close]
  #      Close this connection.
  #
  # The protocol instance returned by #open_server().accept() must have
  # the following methods:
  #
  # [recv_request]
  #     Receive a request from the client and return a [object, message,
  #     args, block] tuple.  This is most easily implemented by calling
  #     DRbMessage.recv_request, providing a stream that sits on top of
  #     the current protocol.
  # [send_reply(succ, result)]
  #     Send a reply to the client.  This is most easily implemented
  #     by calling DRbMessage.send_reply, providing a stream that sits
  #     on top of the current protocol.
  # [close]
  #     Close this connection.
  #
  # A new protocol is registered with the DRbProtocol module using
  # the add_protocol method.
  #
  # For examples of other protocols, see DRbUNIXSocket in drb/unix.rb,
  # and HTTP0 in sample/http0.rb and sample/http0serv.rb in the full
  # drb distribution.
  module DRbProtocol

    # Add a new protocol to the DRbProtocol module.
    def add_protocol(prot)
      @protocol.push(prot)
    end
    module_function :add_protocol

    # Open a client connection to +uri+ with the configuration +config+.
    #
    # The DRbProtocol module asks each registered protocol in turn to
    # try to open the URI.  Each protocol signals that it does not handle that
    # URI by raising a DRbBadScheme error.  If no protocol recognises the
    # URI, then a DRbBadURI error is raised.  If a protocol accepts the
    # URI, but an error occurs in opening it, a DRbConnError is raised.
    def open(uri, config, first=true)
      @protocol.each do |prot|
        begin
          return prot.open(uri, config)
        rescue DRbBadScheme
        rescue DRbConnError
          raise($!)
        rescue
          raise(DRbConnError, "#{uri} - #{$!.inspect}")
        end
      end
      if first && (config[:auto_load] != false)
        auto_load(uri)
        return open(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :open

    # Open a server listening for connections at +uri+ with
    # configuration +config+.
    #
    # The DRbProtocol module asks each registered protocol in turn to
    # try to open a server at the URI.  Each protocol signals that it does
    # not handle that URI by raising a DRbBadScheme error.  If no protocol
    # recognises the URI, then a DRbBadURI error is raised.  If a protocol
    # accepts the URI, but an error occurs in opening it, the underlying
    # error is passed on to the caller.
    def open_server(uri, config, first=true)
      @protocol.each do |prot|
        begin
          return prot.open_server(uri, config)
        rescue DRbBadScheme
        end
      end
      if first && (config[:auto_load] != false)
        auto_load(uri)
        return open_server(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :open_server

    # Parse +uri+ into a [uri, option] pair.
    #
    # The DRbProtocol module asks each registered protocol in turn to
    # try to parse the URI.  Each protocol signals that it does not handle that
    # URI by raising a DRbBadScheme error.  If no protocol recognises the
    # URI, then a DRbBadURI error is raised.
    def uri_option(uri, config, first=true)
      @protocol.each do |prot|
        begin
          uri, opt = prot.uri_option(uri, config)
          # opt = nil if opt == ''
          return uri, opt
        rescue DRbBadScheme
        end
      end
      if first && (config[:auto_load] != false)
        auto_load(uri)
        return uri_option(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :uri_option

    def auto_load(uri)  # :nodoc:
      if /\Adrb([a-z0-9]+):/ =~ uri
        require("drb/#{$1}") rescue nil
      end
    end
    module_function :auto_load
  end

  # The default drb protocol which communicates over a TCP socket.
  #
  # The DRb TCP protocol URI looks like:
  # <code>druby://<host>:<port>?<option></code>.  The option is optional.

  class DRbTCPSocket
    # :stopdoc:
    private
    def self.parse_uri(uri)
      if /\Adruby:\/\/(.*?):(\d+)(\?(.*))?\z/ =~ uri
        host = $1
        port = $2.to_i
        option = $4
        [host, port, option]
      else
        raise(DRbBadScheme, uri) unless uri.start_with?('druby:')
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
    end

    public

    # Open a client connection to +uri+ (DRb URI string) using configuration
    # +config+.
    #
    # This can raise DRb::DRbBadScheme or DRb::DRbBadURI if +uri+ is not for a
    # recognized protocol.  See DRb::DRbServer.new for information on built-in
    # URI protocols.
    def self.open(uri, config)
      host, port, = parse_uri(uri)
      soc = TCPSocket.open(host, port)
      self.new(uri, soc, config)
    end

    # Returns the hostname of this server
    def self.getservername
      host = Socket::gethostname
      begin
        Socket::getaddrinfo(host, nil,
                                  Socket::AF_UNSPEC,
                                  Socket::SOCK_STREAM,
                                  0,
                                  Socket::AI_PASSIVE)[0][3]
      rescue
        'localhost'
      end
    end

    # For the families available for +host+, returns a TCPServer on +port+.
    # If +port+ is 0 the first available port is used.  IPv4 servers are
    # preferred over IPv6 servers.
    def self.open_server_inaddr_any(host, port)
      infos = Socket::getaddrinfo(host, nil,
                                  Socket::AF_UNSPEC,
                                  Socket::SOCK_STREAM,
                                  0,
                                  Socket::AI_PASSIVE)
      families = Hash[*infos.collect { |af, *_| af }.uniq.zip([]).flatten]
      return TCPServer.open('0.0.0.0', port) if families.has_key?('AF_INET')
      return TCPServer.open('::', port) if families.has_key?('AF_INET6')
      return TCPServer.open(port)
      # :stopdoc:
    end

    # Open a server listening for connections at +uri+ using
    # configuration +config+.
    def self.open_server(uri, config)
      uri = 'druby://:0' unless uri
      host, port, _ = parse_uri(uri)
      config = {:tcp_original_host => host}.update(config)
      if host.size == 0
        host = getservername
        soc = open_server_inaddr_any(host, port)
      else
        soc = TCPServer.open(host, port)
      end
      port = soc.addr[1] if port == 0
      config[:tcp_port] = port
      uri = "druby://#{host}:#{port}"
      self.new(uri, soc, config)
    end

    # Parse +uri+ into a [uri, option] pair.
    def self.uri_option(uri, config)
      host, port, option = parse_uri(uri)
      return "druby://#{host}:#{port}", option
    end

    # Create a new DRbTCPSocket instance.
    #
    # +uri+ is the URI we are connected to.
    # +soc+ is the tcp socket we are bound to.  +config+ is our
    # configuration.
    def initialize(uri, soc, config={})
      @uri = uri
      @socket = soc
      @config = config
      @acl = config[:tcp_acl]
      @msg = DRbMessage.new(config)
      set_sockopt(@socket)
      @shutdown_pipe_r, @shutdown_pipe_w = IO.pipe
    end

    # Get the URI that we are connected to.
    attr_reader :uri

    # Get the address of our TCP peer (the other end of the socket
    # we are bound to.
    def peeraddr
      @socket.peeraddr
    end

    # Get the socket.
    def stream; @socket; end

    # On the client side, send a request to the server.
    def send_request(ref, msg_id, arg, b)
      @msg.send_request(stream, ref, msg_id, arg, b)
    end

    # On the server side, receive a request from the client.
    def recv_request
      @msg.recv_request(stream)
    end

    # On the server side, send a reply to the client.
    def send_reply(succ, result)
      @msg.send_reply(stream, succ, result)
    end

    # On the client side, receive a reply from the server.
    def recv_reply
      @msg.recv_reply(stream)
    end

    public

    # Close the connection.
    #
    # If this is an instance returned by #open_server, then this stops
    # listening for new connections altogether.  If this is an instance
    # returned by #open or by #accept, then it closes this particular
    # client-server session.
    def close
      shutdown
      if @socket
        @socket.close
        @socket = nil
      end
      close_shutdown_pipe
    end

    def close_shutdown_pipe
      @shutdown_pipe_w.close
      @shutdown_pipe_r.close
    end
    private :close_shutdown_pipe

    # On the server side, for an instance returned by #open_server,
    # accept a client connection and return a new instance to handle
    # the server's side of this client-server session.
    def accept
      while true
        s = accept_or_shutdown
        return nil unless s
        break if (@acl ? @acl.allow_socket?(s) : true)
        s.close
      end
      if @config[:tcp_original_host].to_s.size == 0
        uri = "druby://#{s.addr[3]}:#{@config[:tcp_port]}"
      else
        uri = @uri
      end
      self.class.new(uri, s, @config)
    end

    def accept_or_shutdown
      readables, = IO.select([@socket, @shutdown_pipe_r])
      if readables.include? @shutdown_pipe_r
        return nil
      end
      @socket.accept
    end
    private :accept_or_shutdown

    # Graceful shutdown
    def shutdown
      @shutdown_pipe_w.close
    end

    # Check to see if this connection is alive.
    def alive?
      return false unless @socket
      if @socket.to_io.wait_readable(0)
        close
        return false
      end
      true
    end

    def set_sockopt(soc) # :nodoc:
      soc.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    rescue IOError, Errno::ECONNRESET, Errno::EINVAL
      # closed/shutdown socket, ignore error
    end
  end

  module DRbProtocol
    @protocol = [DRbTCPSocket] # default
  end

  class DRbURIOption  # :nodoc:  I don't understand the purpose of this class...
    def initialize(option)
      @option = option.to_s
    end
    attr_reader :option
    def to_s; @option; end

    def ==(other)
      return false unless DRbURIOption === other
      @option == other.option
    end

    def hash
      @option.hash
    end

    alias eql? ==
  end

  # Object wrapping a reference to a remote drb object.
  #
  # Method calls on this object are relayed to the remote
  # object that this object is a stub for.
  class DRbObject

    # Unmarshall a marshalled DRbObject.
    #
    # If the referenced object is located within the local server, then
    # the object itself is returned.  Otherwise, a new DRbObject is
    # created to act as a stub for the remote referenced object.
    def self._load(s)
      uri, ref = Marshal.load(s)

      if DRb.here?(uri)
        obj = DRb.to_obj(ref)
        return obj
      end

      self.new_with(uri, ref)
    end

    # Creates a DRb::DRbObject given the reference information to the remote
    # host +uri+ and object +ref+.

    def self.new_with(uri, ref)
      it = self.allocate
      it.instance_variable_set(:@uri, uri)
      it.instance_variable_set(:@ref, ref)
      it
    end

    # Create a new DRbObject from a URI alone.
    def self.new_with_uri(uri)
      self.new(nil, uri)
    end

    # Marshall this object.
    #
    # The URI and ref of the object are marshalled.
    def _dump(lv)
      Marshal.dump([@uri, @ref])
    end

    # Create a new remote object stub.
    #
    # +obj+ is the (local) object we want to create a stub for.  Normally
    # this is +nil+.  +uri+ is the URI of the remote object that this
    # will be a stub for.
    def initialize(obj, uri=nil)
      @uri = nil
      @ref = nil
      case obj
      when Object
        is_nil = obj.nil?
      when BasicObject
        is_nil = false
      end

      if is_nil
        return if uri.nil?
        @uri, option = DRbProtocol.uri_option(uri, DRb.config)
        @ref = DRbURIOption.new(option) unless option.nil?
      else
        @uri = uri ? uri : (DRb.uri rescue nil)
        @ref = obj ? DRb.to_id(obj) : nil
      end
    end

    # Get the URI of the remote object.
    def __drburi
      @uri
    end

    # Get the reference of the object, if local.
    def __drbref
      @ref
    end

    undef :to_s
    undef :to_a if respond_to?(:to_a)

    # Routes respond_to? to the referenced remote object.
    def respond_to?(msg_id, priv=false)
      case msg_id
      when :_dump
        true
      when :marshal_dump
        false
      else
        method_missing(:respond_to?, msg_id, priv)
      end
    end

    # Routes method calls to the referenced remote object.
    ruby2_keywords def method_missing(msg_id, *a, &b)
      if DRb.here?(@uri)
        obj = DRb.to_obj(@ref)
        DRb.current_server.check_insecure_method(obj, msg_id)
        return obj.__send__(msg_id, *a, &b)
      end

      succ, result = self.class.with_friend(@uri) do
        DRbConn.open(@uri) do |conn|
          conn.send_message(self, msg_id, a, b)
        end
      end

      if succ
        return result
      elsif DRbUnknown === result
        raise result
      else
        bt = self.class.prepare_backtrace(@uri, result)
        result.set_backtrace(bt + caller)
        raise result
      end
    end

    # Given the +uri+ of another host executes the block provided.
    def self.with_friend(uri) # :nodoc:
      friend = DRb.fetch_server(uri)
      return yield() unless friend

      save = Thread.current['DRb']
      Thread.current['DRb'] = { 'server' => friend }
      return yield
    ensure
      Thread.current['DRb'] = save if friend
    end

    # Returns a modified backtrace from +result+ with the +uri+ where each call
    # in the backtrace came from.
    def self.prepare_backtrace(uri, result) # :nodoc:
      prefix = "(#{uri}) "
      bt = []
      result.backtrace.each do |x|
        break if /`__send__'$/ =~ x
        if /\A\(druby:\/\// =~ x
          bt.push(x)
        else
          bt.push(prefix + x)
        end
      end
      bt
    end

    def pretty_print(q)   # :nodoc:
      q.pp_object(self)
    end

    def pretty_print_cycle(q)   # :nodoc:
      q.object_address_group(self) {
        q.breakable
        q.text '...'
      }
    end
  end

  class ThreadObject
    include MonitorMixin

    def initialize(&blk)
      super()
      @wait_ev = new_cond
      @req_ev = new_cond
      @res_ev = new_cond
      @status = :wait
      @req = nil
      @res = nil
      @thread = Thread.new(self, &blk)
    end

    def alive?
      @thread.alive?
    end

    def kill
      @thread.kill
      @thread.join
    end

    def method_missing(msg, *arg, &blk)
      synchronize do
        @wait_ev.wait_until { @status == :wait }
        @req = [msg] + arg
        @status = :req
        @req_ev.broadcast
        @res_ev.wait_until { @status == :res }
        value = @res
        @req = @res = nil
        @status = :wait
        @wait_ev.broadcast
        return value
      end
    end

    def _execute()
      synchronize do
        @req_ev.wait_until { @status == :req }
        @res = yield(@req)
        @status = :res
        @res_ev.signal
      end
    end
  end

  # Class handling the connection between a DRbObject and the
  # server the real object lives on.
  #
  # This class maintains a pool of connections, to reduce the
  # overhead of starting and closing down connections for each
  # method call.
  #
  # This class is used internally by DRbObject.  The user does
  # not normally need to deal with it directly.
  class DRbConn
    POOL_SIZE = 16  # :nodoc:

    def self.make_pool
      ThreadObject.new do |queue|
        pool = []
        while true
          queue._execute do |message|
            case(message[0])
            when :take then
              remote_uri = message[1]
              conn = nil
              new_pool = []
              pool.each do |c|
                if conn.nil? and c.uri == remote_uri
                  conn = c if c.alive?
                else
                  new_pool.push c
                end
              end
              pool = new_pool
              conn
            when :store then
              conn = message[1]
              pool.unshift(conn)
              pool.pop.close while pool.size > POOL_SIZE
              conn
            else
              nil
            end
          end
        end
      end
    end
    @pool_proxy = nil

    def self.stop_pool
      @pool_proxy&.kill
      @pool_proxy = nil
    end

    def self.open(remote_uri)  # :nodoc:
      begin
        @pool_proxy = make_pool unless @pool_proxy&.alive?

        conn = @pool_proxy.take(remote_uri)
        conn = self.new(remote_uri) unless conn
        succ, result = yield(conn)
        return succ, result

      ensure
        if conn
          if succ
            @pool_proxy.store(conn)
          else
            conn.close
          end
        end
      end
    end

    def initialize(remote_uri)  # :nodoc:
      @uri = remote_uri
      @protocol = DRbProtocol.open(remote_uri, DRb.config)
    end
    attr_reader :uri  # :nodoc:

    def send_message(ref, msg_id, arg, block)  # :nodoc:
      @protocol.send_request(ref, msg_id, arg, block)
      @protocol.recv_reply
    end

    def close  # :nodoc:
      @protocol.close
      @protocol = nil
    end

    def alive?  # :nodoc:
      return false unless @protocol
      @protocol.alive?
    end
  end

  # Class representing a drb server instance.
  #
  # A DRbServer must be running in the local process before any incoming
  # dRuby calls can be accepted, or any local objects can be passed as
  # dRuby references to remote processes, even if those local objects are
  # never actually called remotely. You do not need to start a DRbServer
  # in the local process if you are only making outgoing dRuby calls
  # passing marshalled parameters.
  #
  # Unless multiple servers are being used, the local DRbServer is normally
  # started by calling DRb.start_service.
  class DRbServer
    @@acl = nil
    @@idconv = DRbIdConv.new
    @@secondary_server = nil
    @@argc_limit = 256
    @@load_limit = 0xffffffff
    @@verbose = false

    # Set the default value for the :argc_limit option.
    #
    # See #new().  The initial default value is 256.
    def self.default_argc_limit(argc)
      @@argc_limit = argc
    end

    # Set the default value for the :load_limit option.
    #
    # See #new().  The initial default value is 25 MB.
    def self.default_load_limit(sz)
      @@load_limit = sz
    end

    # Set the default access control list to +acl+.  The default ACL is +nil+.
    #
    # See also DRb::ACL and #new()
    def self.default_acl(acl)
      @@acl = acl
    end

    # Set the default value for the :id_conv option.
    #
    # See #new().  The initial default value is a DRbIdConv instance.
    def self.default_id_conv(idconv)
      @@idconv = idconv
    end

    # Set the default value of the :verbose option.
    #
    # See #new().  The initial default value is false.
    def self.verbose=(on)
      @@verbose = on
    end

    # Get the default value of the :verbose option.
    def self.verbose
      @@verbose
    end

    def self.make_config(hash={})  # :nodoc:
      default_config = {
        :idconv => @@idconv,
        :verbose => @@verbose,
        :tcp_acl => @@acl,
        :load_limit => @@load_limit,
        :argc_limit => @@argc_limit,
      }
      default_config.update(hash)
    end

    # Create a new DRbServer instance.
    #
    # +uri+ is the URI to bind to.  This is normally of the form
    # 'druby://<hostname>:<port>' where <hostname> is a hostname of
    # the local machine.  If nil, then the system's default hostname
    # will be bound to, on a port selected by the system; these value
    # can be retrieved from the +uri+ attribute.  'druby:' specifies
    # the default dRuby transport protocol: another protocol, such
    # as 'drbunix:', can be specified instead.
    #
    # +front+ is the front object for the server, that is, the object
    # to which remote method calls on the server will be passed.  If
    # nil, then the server will not accept remote method calls.
    #
    # If +config_or_acl+ is a hash, it is the configuration to
    # use for this server.  The following options are recognised:
    #
    # :idconv :: an id-to-object conversion object.  This defaults
    #            to an instance of the class DRb::DRbIdConv.
    # :verbose :: if true, all unsuccessful remote calls on objects
    #             in the server will be logged to $stdout. false
    #             by default.
    # :tcp_acl :: the access control list for this server.  See
    #             the ACL class from the main dRuby distribution.
    # :load_limit :: the maximum message size in bytes accepted by
    #                the server.  Defaults to 25 MB (26214400).
    # :argc_limit :: the maximum number of arguments to a remote
    #                method accepted by the server.  Defaults to
    #                256.
    # The default values of these options can be modified on
    # a class-wide basis by the class methods #default_argc_limit,
    # #default_load_limit, #default_acl, #default_id_conv,
    # and #verbose=
    #
    # If +config_or_acl+ is not a hash, but is not nil, it is
    # assumed to be the access control list for this server.
    # See the :tcp_acl option for more details.
    #
    # If no other server is currently set as the primary server,
    # this will become the primary server.
    #
    # The server will immediately start running in its own thread.
    def initialize(uri=nil, front=nil, config_or_acl=nil)
      if Hash === config_or_acl
        config = config_or_acl.dup
      else
        acl = config_or_acl || @@acl
        config = {
          :tcp_acl => acl
        }
      end

      @config = self.class.make_config(config)

      @protocol = DRbProtocol.open_server(uri, @config)
      @uri = @protocol.uri
      @exported_uri = [@uri]

      @front = front
      @idconv = @config[:idconv]

      @grp = ThreadGroup.new
      @thread = run

      DRb.regist_server(self)
    end

    # The URI of this DRbServer.
    attr_reader :uri

    # The main thread of this DRbServer.
    #
    # This is the thread that listens for and accepts connections
    # from clients, not that handles each client's request-response
    # session.
    attr_reader :thread

    # The front object of the DRbServer.
    #
    # This object receives remote method calls made on the server's
    # URI alone, with an object id.
    attr_reader :front

    # The configuration of this DRbServer
    attr_reader :config

    # Set whether to operate in verbose mode.
    #
    # In verbose mode, failed calls are logged to stdout.
    def verbose=(v); @config[:verbose]=v; end

    # Get whether the server is in verbose mode.
    #
    # In verbose mode, failed calls are logged to stdout.
    def verbose; @config[:verbose]; end

    # Is this server alive?
    def alive?
      @thread.alive?
    end

    # Is +uri+ the URI for this server?
    def here?(uri)
      @exported_uri.include?(uri)
    end

    # Stop this server.
    def stop_service
      DRb.remove_server(self)
      if  Thread.current['DRb'] && Thread.current['DRb']['server'] == self
        Thread.current['DRb']['stop_service'] = true
      else
        shutdown
      end
    end

    # Convert a dRuby reference to the local object it refers to.
    def to_obj(ref)
      return front if ref.nil?
      return front[ref.to_s] if DRbURIOption === ref
      @idconv.to_obj(ref)
    end

    # Convert a local object to a dRuby reference.
    def to_id(obj)
      return nil if obj.__id__ == front.__id__
      @idconv.to_id(obj)
    end

    private

    def shutdown
      current = Thread.current
      if @protocol.respond_to? :shutdown
        @protocol.shutdown
      else
        [@thread, *@grp.list].each { |thread|
          thread.kill unless thread == current # xxx: Thread#kill
        }
      end
      @thread.join unless @thread == current
    end

    ##
    # Starts the DRb main loop in a new thread.

    def run
      Thread.start do
        begin
          while main_loop
          end
        ensure
          @protocol.close if @protocol
        end
      end
    end

    # List of insecure methods.
    #
    # These methods are not callable via dRuby.
    INSECURE_METHOD = [
      :__send__
    ]

    # Has a method been included in the list of insecure methods?
    def insecure_method?(msg_id)
      INSECURE_METHOD.include?(msg_id)
    end

    # Coerce an object to a string, providing our own representation if
    # to_s is not defined for the object.
    def any_to_s(obj)
      "#{obj}:#{obj.class}"
    rescue
      Kernel.instance_method(:to_s).bind_call(obj)
    end

    # Check that a method is callable via dRuby.
    #
    # +obj+ is the object we want to invoke the method on. +msg_id+ is the
    # method name, as a Symbol.
    #
    # If the method is an insecure method (see #insecure_method?) a
    # SecurityError is thrown.  If the method is private or undefined,
    # a NameError is thrown.
    def check_insecure_method(obj, msg_id)
      return true if Proc === obj && msg_id == :__drb_yield
      raise(ArgumentError, "#{any_to_s(msg_id)} is not a symbol") unless Symbol == msg_id.class
      raise(SecurityError, "insecure method `#{msg_id}'") if insecure_method?(msg_id)

      case obj
      when Object
        if obj.private_methods.include?(msg_id)
          desc = any_to_s(obj)
          raise NoMethodError, "private method `#{msg_id}' called for #{desc}"
        elsif obj.protected_methods.include?(msg_id)
          desc = any_to_s(obj)
          raise NoMethodError, "protected method `#{msg_id}' called for #{desc}"
        else
          true
        end
      else
        if Kernel.instance_method(:private_methods).bind(obj).call.include?(msg_id)
          desc = any_to_s(obj)
          raise NoMethodError, "private method `#{msg_id}' called for #{desc}"
        elsif Kernel.instance_method(:protected_methods).bind(obj).call.include?(msg_id)
          desc = any_to_s(obj)
          raise NoMethodError, "protected method `#{msg_id}' called for #{desc}"
        else
          true
        end
      end
    end
    public :check_insecure_method

    class InvokeMethod  # :nodoc:
      def initialize(drb_server, client)
        @drb_server = drb_server
        @client = client
      end

      def perform
        @result = nil
        @succ = false
        setup_message

        if @block
          @result = perform_with_block
        else
          @result = perform_without_block
        end
        @succ = true
        case @result
        when Array
          if @msg_id == :to_ary
            @result = DRbArray.new(@result)
          end
        end
        return @succ, @result
      rescue NoMemoryError, SystemExit, SystemStackError, SecurityError
        raise
      rescue Exception
        @result = $!
        return @succ, @result
      end

      private
      def init_with_client
        obj, msg, argv, block = @client.recv_request
        @obj = obj
        @msg_id = msg.intern
        @argv = argv
        @block = block
      end

      def check_insecure_method
        @drb_server.check_insecure_method(@obj, @msg_id)
      end

      def setup_message
        init_with_client
        check_insecure_method
      end

      def perform_without_block
        if Proc === @obj && @msg_id == :__drb_yield
          if @argv.size == 1
            ary = @argv
          else
            ary = [@argv]
          end
          ary.collect(&@obj)[0]
        else
          @obj.__send__(@msg_id, *@argv)
        end
      end

    end

    require_relative 'invokemethod'
    class InvokeMethod
      include InvokeMethod18Mixin
    end

    def error_print(exception)
      exception.backtrace.inject(true) do |first, x|
        if first
          $stderr.puts "#{x}: #{exception} (#{exception.class})"
        else
          $stderr.puts "\tfrom #{x}"
        end
        false
      end
    end

    # The main loop performed by a DRbServer's internal thread.
    #
    # Accepts a connection from a client, and starts up its own
    # thread to handle it.  This thread loops, receiving requests
    # from the client, invoking them on a local object, and
    # returning responses, until the client closes the connection
    # or a local method call fails.
    def main_loop
      client0 = @protocol.accept
      return nil if !client0
      Thread.start(client0) do |client|
        @grp.add Thread.current
        Thread.current['DRb'] = { 'client' => client ,
                                  'server' => self }
        DRb.mutex.synchronize do
          client_uri = client.uri
          @exported_uri << client_uri unless @exported_uri.include?(client_uri)
        end
        loop do
          begin
            succ = false
            invoke_method = InvokeMethod.new(self, client)
            succ, result = invoke_method.perform
            error_print(result) if !succ && verbose
            unless DRbConnError === result && result.message == 'connection closed'
              client.send_reply(succ, result)
            end
          rescue Exception => e
            error_print(e) if verbose
          ensure
            client.close unless succ
            if Thread.current['DRb']['stop_service']
              shutdown
              break
            end
            break unless succ
          end
        end
      end
    end
  end

  @primary_server = nil

  # Start a dRuby server locally.
  #
  # The new dRuby server will become the primary server, even
  # if another server is currently the primary server.
  #
  # +uri+ is the URI for the server to bind to.  If nil,
  # the server will bind to random port on the default local host
  # name and use the default dRuby protocol.
  #
  # +front+ is the server's front object.  This may be nil.
  #
  # +config+ is the configuration for the new server.  This may
  # be nil.
  #
  # See DRbServer::new.
  def start_service(uri=nil, front=nil, config=nil)
    @primary_server = DRbServer.new(uri, front, config)
  end
  module_function :start_service

  # The primary local dRuby server.
  #
  # This is the server created by the #start_service call.
  attr_accessor :primary_server
  module_function :primary_server=, :primary_server

  # Get the 'current' server.
  #
  # In the context of execution taking place within the main
  # thread of a dRuby server (typically, as a result of a remote
  # call on the server or one of its objects), the current
  # server is that server.  Otherwise, the current server is
  # the primary server.
  #
  # If the above rule fails to find a server, a DRbServerNotFound
  # error is raised.
  def current_server
    drb = Thread.current['DRb']
    server = (drb && drb['server']) ? drb['server'] : @primary_server
    raise DRbServerNotFound unless server
    return server
  end
  module_function :current_server

  # Stop the local dRuby server.
  #
  # This operates on the primary server.  If there is no primary
  # server currently running, it is a noop.
  def stop_service
    @primary_server.stop_service if @primary_server
    @primary_server = nil
  end
  module_function :stop_service

  # Get the URI defining the local dRuby space.
  #
  # This is the URI of the current server.  See #current_server.
  def uri
    drb = Thread.current['DRb']
    client = (drb && drb['client'])
    if client
      uri = client.uri
      return uri if uri
    end
    current_server.uri
  end
  module_function :uri

  # Is +uri+ the URI for the current local server?
  def here?(uri)
    current_server.here?(uri) rescue false
    # (current_server.uri rescue nil) == uri
  end
  module_function :here?

  # Get the configuration of the current server.
  #
  # If there is no current server, this returns the default configuration.
  # See #current_server and DRbServer::make_config.
  def config
    current_server.config
  rescue
    DRbServer.make_config
  end
  module_function :config

  # Get the front object of the current server.
  #
  # This raises a DRbServerNotFound error if there is no current server.
  # See #current_server.
  def front
    current_server.front
  end
  module_function :front

  # Convert a reference into an object using the current server.
  #
  # This raises a DRbServerNotFound error if there is no current server.
  # See #current_server.
  def to_obj(ref)
    current_server.to_obj(ref)
  end

  # Get a reference id for an object using the current server.
  #
  # This raises a DRbServerNotFound error if there is no current server.
  # See #current_server.
  def to_id(obj)
    current_server.to_id(obj)
  end
  module_function :to_id
  module_function :to_obj

  # Get the thread of the primary server.
  #
  # This returns nil if there is no primary server.  See #primary_server.
  def thread
    @primary_server ? @primary_server.thread : nil
  end
  module_function :thread

  # Set the default id conversion object.
  #
  # This is expected to be an instance such as DRb::DRbIdConv that responds to
  # #to_id and #to_obj that can convert objects to and from DRb references.
  #
  # See DRbServer#default_id_conv.
  def install_id_conv(idconv)
    DRbServer.default_id_conv(idconv)
  end
  module_function :install_id_conv

  # Set the default ACL to +acl+.
  #
  # See DRb::DRbServer.default_acl.
  def install_acl(acl)
    DRbServer.default_acl(acl)
  end
  module_function :install_acl

  @mutex = Thread::Mutex.new
  def mutex # :nodoc:
    @mutex
  end
  module_function :mutex

  @server = {}
  # Registers +server+ with DRb.
  #
  # This is called when a new DRb::DRbServer is created.
  #
  # If there is no primary server then +server+ becomes the primary server.
  #
  # Example:
  #
  #  require 'drb'
  #
  #  s = DRb::DRbServer.new # automatically calls regist_server
  #  DRb.fetch_server s.uri #=> #<DRb::DRbServer:0x...>
  def regist_server(server)
    @server[server.uri] = server
    mutex.synchronize do
      @primary_server = server unless @primary_server
    end
  end
  module_function :regist_server

  # Removes +server+ from the list of registered servers.
  def remove_server(server)
    @server.delete(server.uri)
    mutex.synchronize do
      if @primary_server == server
        @primary_server = nil
      end
    end
  end
  module_function :remove_server

  # Retrieves the server with the given +uri+.
  #
  # See also regist_server and remove_server.
  def fetch_server(uri)
    @server[uri]
  end
  module_function :fetch_server
end

# :stopdoc:
DRbObject = DRb::DRbObject
DRbUndumped = DRb::DRbUndumped
DRbIdConv = DRb::DRbIdConv
