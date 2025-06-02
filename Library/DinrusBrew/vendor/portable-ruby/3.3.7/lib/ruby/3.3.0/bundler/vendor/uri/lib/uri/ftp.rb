# frozen_string_literal: false
# = uri/ftp.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See Bundler::URI for general documentation
#

require_relative 'generic'

module Bundler::URI

  #
  # FTP Bundler::URI syntax is defined by RFC1738 section 3.2.
  #
  # This class will be redesigned because of difference of implementations;
  # the structure of its path. draft-hoffman-ftp-uri-04 is a draft but it
  # is a good summary about the de facto spec.
  # http://tools.ietf.org/html/draft-hoffman-ftp-uri-04
  #
  class FTP < Generic
    # A Default port of 21 for Bundler::URI::FTP.
    DEFAULT_PORT = 21

    #
    # An Array of the available components for Bundler::URI::FTP.
    #
    COMPONENT = [
      :scheme,
      :userinfo, :host, :port,
      :path, :typecode
    ].freeze

    #
    # Typecode is "a", "i", or "d".
    #
    # * "a" indicates a text file (the FTP command was ASCII)
    # * "i" indicates a binary file (FTP command IMAGE)
    # * "d" indicates the contents of a directory should be displayed
    #
    TYPECODE = ['a', 'i', 'd'].freeze

    # Typecode prefix ";type=".
    TYPECODE_PREFIX = ';type='.freeze

    def self.new2(user, password, host, port, path,
                  typecode = nil, arg_check = true) # :nodoc:
      # Do not use this method!  Not tested.  [Bug #7301]
      # This methods remains just for compatibility,
      # Keep it undocumented until the active maintainer is assigned.
      typecode = nil if typecode.size == 0
      if typecode && !TYPECODE.include?(typecode)
        raise ArgumentError,
          "bad typecode is specified: #{typecode}"
      end

      # do escape

      self.new('ftp',
               [user, password],
               host, port, nil,
               typecode ? path + TYPECODE_PREFIX + typecode : path,
               nil, nil, nil, arg_check)
    end

    #
    # == Description
    #
    # Creates a new Bundler::URI::FTP object from components, with syntax checking.
    #
    # The components accepted are +userinfo+, +host+, +port+, +path+, and
    # +typecode+.
    #
    # The components should be provided either as an Array, or as a Hash
    # with keys formed by preceding the component names with a colon.
    #
    # If an Array is used, the components must be passed in the
    # order <code>[userinfo, host, port, path, typecode]</code>.
    #
    # If the path supplied is absolute, it will be escaped in order to
    # make it absolute in the Bundler::URI.
    #
    # Examples:
    #
    #     require 'bundler/vendor/uri/lib/uri'
    #
    #     uri1 = Bundler::URI::FTP.build(['user:password', 'ftp.example.com', nil,
    #       '/path/file.zip', 'i'])
    #     uri1.to_s  # => "ftp://user:password@ftp.example.com/%2Fpath/file.zip;type=i"
    #
    #     uri2 = Bundler::URI::FTP.build({:host => 'ftp.example.com',
    #       :path => 'ruby/src'})
    #     uri2.to_s  # => "ftp://ftp.example.com/ruby/src"
    #
    def self.build(args)

      # Fix the incoming path to be generic URL syntax
      # FTP path  ->  URL path
      # foo/bar       /foo/bar
      # /foo/bar      /%2Ffoo/bar
      #
      if args.kind_of?(Array)
        args[3] = '/' + args[3].sub(/^\//, '%2F')
      else
        args[:path] = '/' + args[:path].sub(/^\//, '%2F')
      end

      tmp = Util::make_components_hash(self, args)

      if tmp[:typecode]
        if tmp[:typecode].size == 1
          tmp[:typecode] = TYPECODE_PREFIX + tmp[:typecode]
        end
        tmp[:path] << tmp[:typecode]
      end

      return super(tmp)
    end

    #
    # == Description
    #
    # Creates a new Bundler::URI::FTP object from generic URL components with no
    # syntax checking.
    #
    # Unlike build(), this method does not escape the path component as
    # required by RFC1738; instead it is treated as per RFC2396.
    #
    # Arguments are +scheme+, +userinfo+, +host+, +port+, +registry+, +path+,
    # +opaque+, +query+, and +fragment+, in that order.
    #
    def initialize(scheme,
                   userinfo, host, port, registry,
                   path, opaque,
                   query,
                   fragment,
                   parser = nil,
                   arg_check = false)
      raise InvalidURIError unless path
      path = path.sub(/^\//,'')
      path.sub!(/^%2F/,'/')
      super(scheme, userinfo, host, port, registry, path, opaque,
            query, fragment, parser, arg_check)
      @typecode = nil
      if tmp = @path.index(TYPECODE_PREFIX)
        typecode = @path[tmp + TYPECODE_PREFIX.size..-1]
        @path = @path[0..tmp - 1]

        if arg_check
          self.typecode = typecode
        else
          self.set_typecode(typecode)
        end
      end
    end

    # typecode accessor.
    #
    # See Bundler::URI::FTP::COMPONENT.
    attr_reader :typecode

    # Validates typecode +v+,
    # returns +true+ or +false+.
    #
    def check_typecode(v)
      if TYPECODE.include?(v)
        return true
      else
        raise InvalidComponentError,
          "bad typecode(expected #{TYPECODE.join(', ')}): #{v}"
      end
    end
    private :check_typecode

    # Private setter for the typecode +v+.
    #
    # See also Bundler::URI::FTP.typecode=.
    #
    def set_typecode(v)
      @typecode = v
    end
    protected :set_typecode

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the typecode +v+
    # (with validation).
    #
    # See also Bundler::URI::FTP.check_typecode.
    #
    # == Usage
    #
    #   require 'bundler/vendor/uri/lib/uri'
    #
    #   uri = Bundler::URI.parse("ftp://john@ftp.example.com/my_file.img")
    #   #=> #<Bundler::URI::FTP ftp://john@ftp.example.com/my_file.img>
    #   uri.typecode = "i"
    #   uri
    #   #=> #<Bundler::URI::FTP ftp://john@ftp.example.com/my_file.img;type=i>
    #
    def typecode=(typecode)
      check_typecode(typecode)
      set_typecode(typecode)
      typecode
    end

    def merge(oth) # :nodoc:
      tmp = super(oth)
      if self != tmp
        tmp.set_typecode(oth.typecode)
      end

      return tmp
    end

    # Returns the path from an FTP Bundler::URI.
    #
    # RFC 1738 specifically states that the path for an FTP Bundler::URI does not
    # include the / which separates the Bundler::URI path from the Bundler::URI host. Example:
    #
    # <code>ftp://ftp.example.com/pub/ruby</code>
    #
    # The above Bundler::URI indicates that the client should connect to
    # ftp.example.com then cd to pub/ruby from the initial login directory.
    #
    # If you want to cd to an absolute directory, you must include an
    # escaped / (%2F) in the path. Example:
    #
    # <code>ftp://ftp.example.com/%2Fpub/ruby</code>
    #
    # This method will then return "/pub/ruby".
    #
    def path
      return @path.sub(/^\//,'').sub(/^%2F/,'/')
    end

    # Private setter for the path of the Bundler::URI::FTP.
    def set_path(v)
      super("/" + v.sub(/^\//, "%2F"))
    end
    protected :set_path

    # Returns a String representation of the Bundler::URI::FTP.
    def to_s
      save_path = nil
      if @typecode
        save_path = @path
        @path = @path + TYPECODE_PREFIX + @typecode
      end
      str = super
      if @typecode
        @path = save_path
      end

      return str
    end
  end

  register_scheme 'FTP', FTP
end
