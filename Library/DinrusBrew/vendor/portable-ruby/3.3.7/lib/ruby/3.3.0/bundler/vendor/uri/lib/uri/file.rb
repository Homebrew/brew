# frozen_string_literal: true

require_relative 'generic'

module Bundler::URI

  #
  # The "file" Bundler::URI is defined by RFC8089.
  #
  class File < Generic
    # A Default port of nil for Bundler::URI::File.
    DEFAULT_PORT = nil

    #
    # An Array of the available components for Bundler::URI::File.
    #
    COMPONENT = [
      :scheme,
      :host,
      :path
    ].freeze

    #
    # == Description
    #
    # Creates a new Bundler::URI::File object from components, with syntax checking.
    #
    # The components accepted are +host+ and +path+.
    #
    # The components should be provided either as an Array, or as a Hash
    # with keys formed by preceding the component names with a colon.
    #
    # If an Array is used, the components must be passed in the
    # order <code>[host, path]</code>.
    #
    # A path from e.g. the File class should be escaped before
    # being passed.
    #
    # Examples:
    #
    #     require 'bundler/vendor/uri/lib/uri'
    #
    #     uri1 = Bundler::URI::File.build(['host.example.com', '/path/file.zip'])
    #     uri1.to_s  # => "file://host.example.com/path/file.zip"
    #
    #     uri2 = Bundler::URI::File.build({:host => 'host.example.com',
    #       :path => '/ruby/src'})
    #     uri2.to_s  # => "file://host.example.com/ruby/src"
    #
    #     uri3 = Bundler::URI::File.build({:path => Bundler::URI::escape('/path/my file.txt')})
    #     uri3.to_s  # => "file:///path/my%20file.txt"
    #
    def self.build(args)
      tmp = Util::make_components_hash(self, args)
      super(tmp)
    end

    # Protected setter for the host component +v+.
    #
    # See also Bundler::URI::Generic.host=.
    #
    def set_host(v)
      v = "" if v.nil? || v == "localhost"
      @host = v
    end

    # do nothing
    def set_port(v)
    end

    # raise InvalidURIError
    def check_userinfo(user)
      raise Bundler::URI::InvalidURIError, "can not set userinfo for file Bundler::URI"
    end

    # raise InvalidURIError
    def check_user(user)
      raise Bundler::URI::InvalidURIError, "can not set user for file Bundler::URI"
    end

    # raise InvalidURIError
    def check_password(user)
      raise Bundler::URI::InvalidURIError, "can not set password for file Bundler::URI"
    end

    # do nothing
    def set_userinfo(v)
    end

    # do nothing
    def set_user(v)
    end

    # do nothing
    def set_password(v)
    end
  end

  register_scheme 'FILE', File
end
