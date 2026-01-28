# typed: strict
# frozen_string_literal: true

require "source_location"
require "utils/curl"

module Cask
  # Class corresponding to the `url` stanza.
  class URL
    sig { returns(URI::Generic) }
    attr_reader :uri

    sig { returns(T.nilable(T::Hash[T.any(Symbol, String), String])) }
    attr_reader :revisions

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :trust_cert

    sig { returns(T.nilable(T::Hash[String, String])) }
    attr_reader :cookies, :data

    sig { returns(T.nilable(T.any(String, T::Array[String]))) }
    attr_reader :header

    sig { returns(T.nilable(T.any(URI::Generic, String))) }
    attr_reader :referer

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :specs

    sig { returns(T.nilable(T.any(Symbol, String))) }
    attr_reader :user_agent

    sig { returns(T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol))) }
    attr_reader :using

    sig { returns(T.nilable(String)) }
    attr_reader :tag, :branch, :revision, :only_path, :verified

    extend Forwardable

    def_delegators :uri, :path, :scheme, :to_s

    # Creates a `url` stanza.
    #
    # @api public
    sig {
      params(
        uri:             T.any(URI::Generic, String),
        verified:        T.nilable(String),
        using:           T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol)),
        tag:             T.nilable(String),
        branch:          T.nilable(String),
        revisions:       T.nilable(T::Hash[T.any(Symbol, String), String]),
        revision:        T.nilable(String),
        trust_cert:      T.nilable(T::Boolean),
        cookies:         T.nilable(T::Hash[T.any(String, Symbol), String]),
        referer:         T.nilable(T.any(URI::Generic, String)),
        header:          T.nilable(T.any(String, T::Array[String])),
        user_agent:      T.nilable(T.any(Symbol, String)),
        data:            T.nilable(T::Hash[String, String]),
        only_path:       T.nilable(String),
        caller_location: Thread::Backtrace::Location,
      ).void
    }
    def initialize(
      uri, verified: nil, using: nil, tag: nil, branch: nil, revisions: nil, revision: nil, trust_cert: nil,
      cookies: nil, referer: nil, header: nil, user_agent: nil, data: nil, only_path: nil,
      caller_location: caller_locations.fetch(0)
    )
      @uri = T.let(URI(uri), URI::Generic)

      header = Array(header) unless header.nil?

      specs = {}
      specs[:verified]   = @verified   = T.let(verified, T.nilable(String))
      specs[:using]      = @using      = T.let(using, T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol)))
      specs[:tag]        = @tag        = T.let(tag, T.nilable(String))
      specs[:branch]     = @branch     = T.let(branch, T.nilable(String))
      specs[:revisions]  = @revisions  = T.let(revisions, T.nilable(T::Hash[T.any(Symbol, String), String]))
      specs[:revision]   = @revision   = T.let(revision, T.nilable(String))
      specs[:trust_cert] = @trust_cert = T.let(trust_cert, T.nilable(T::Boolean))
      specs[:cookies]    =
        @cookies = T.let(cookies&.transform_keys(&:to_s), T.nilable(T::Hash[String, String]))
      specs[:referer]    = @referer    = T.let(referer, T.nilable(T.any(URI::Generic, String)))
      specs[:headers]    = @header     = T.let(header, T.nilable(T.any(String, T::Array[String])))
      specs[:user_agent] = @user_agent = T.let(user_agent || :default, T.nilable(T.any(Symbol, String)))
      specs[:data]       = @data       = T.let(data, T.nilable(T::Hash[String, String]))
      specs[:only_path]  = @only_path  = T.let(only_path, T.nilable(String))

      @specs = T.let(specs.compact, T::Hash[Symbol, T.untyped])
      @caller_location = caller_location
    end

    sig { returns(Homebrew::SourceLocation) }
    def location
      Homebrew::SourceLocation.new(@caller_location.lineno, raw_url_line&.index("url"))
    end

    sig { params(ignore_major_version: T::Boolean).returns(T::Boolean) }
    def unversioned?(ignore_major_version: false)
      interpolated_url = raw_url_line&.then { |line| line[/url\s+"([^"]+)"/, 1] }

      return false unless interpolated_url

      interpolated_url = interpolated_url.gsub(/\#{\s*arch\s*}/, "")
      interpolated_url = interpolated_url.gsub(/\#{\s*version\s*\.major\s*}/, "") if ignore_major_version

      interpolated_url.exclude?('#{')
    end

    private

    sig { returns(T.nilable(String)) }
    def raw_url_line
      return @raw_url_line if defined?(@raw_url_line)

      @raw_url_line = T.let(Pathname(T.must(@caller_location.path))
                      .each_line
                      .drop(@caller_location.lineno - 1)
                      .first, T.nilable(String))
    end
  end
end
