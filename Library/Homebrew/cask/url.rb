# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "source_location"
require "utils/curl"

module Cask
  # Class corresponding to the `url` stanza.
  class URL < SimpleDelegator
    class DSL
      attr_reader :uri, :tag, :branch, :revisions, :revision,
                  :trust_cert, :cookies, :header, :data, :only_path

      sig { returns(T.nilable(T.any(URI::Generic, String))) }
      attr_reader :referer

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :specs

      sig { returns(T.nilable(T.any(Symbol, String))) }
      attr_reader :user_agent

      sig { returns(T.any(T::Class[T.anything], Symbol, NilClass)) }
      attr_reader :using

      sig { returns(T.nilable(String)) }
      attr_reader :verified

      extend Forwardable
      def_delegators :uri, :path, :scheme, :to_s

      sig {
        params(
          uri:        T.any(URI::Generic, String),
          # @api public
          verified:   T.nilable(String),
          # @api public
          using:      T.any(Class, Symbol, NilClass),
          # @api public
          tag:        T.nilable(String),
          # @api public
          branch:     T.nilable(String),
          # @api public
          revisions:  T.nilable(T::Array[String]),
          # @api public
          revision:   T.nilable(String),
          # @api public
          trust_cert: T.nilable(T::Boolean),
          # @api public
          cookies:    T.nilable(T::Hash[String, String]),
          referer:    T.nilable(T.any(URI::Generic, String)),
          # @api public
          header:     T.nilable(T.any(String, T::Array[String])),
          user_agent: T.nilable(T.any(Symbol, String)),
          # @api public
          data:       T.nilable(T::Hash[String, String]),
          # @api public
          only_path:  T.nilable(String),
        ).void
      }
      def initialize(
        uri,
        verified: nil,
        using: nil,
        tag: nil,
        branch: nil,
        revisions: nil,
        revision: nil,
        trust_cert: nil,
        cookies: nil,
        referer: nil,
        header: nil,
        user_agent: nil,
        data: nil,
        only_path: nil
      )
        @uri = URI(uri)

        header = Array(header) unless header.nil?

        specs = {}
        specs[:verified]   = @verified   = verified
        specs[:using]      = @using      = using
        specs[:tag]        = @tag        = tag
        specs[:branch]     = @branch     = branch
        specs[:revisions]  = @revisions  = revisions
        specs[:revision]   = @revision   = revision
        specs[:trust_cert] = @trust_cert = trust_cert
        specs[:cookies]    = @cookies    = cookies
        specs[:referer]    = @referer    = referer
        specs[:headers]    = @header     = header
        specs[:user_agent] = @user_agent = user_agent || :default
        specs[:data]       = @data       = data
        specs[:only_path]  = @only_path  = only_path

        @specs = specs.compact
      end
    end

    class BlockDSL
      # Allow accessing the URL associated with page contents.
      class PageWithURL < SimpleDelegator
        # Get the URL of the fetched page.
        #
        # ### Example
        #
        # ```ruby
        # url "https://example.org/download" do |page|
        #   file_path = page[/href="([^"]+\.dmg)"/, 1]
        #   URI.join(page.url, file_path)
        # end
        # ```
        #
        # @api public
        sig { returns(URI::Generic) }
        attr_accessor :url

        def initialize(str, url)
          super(str)
          @url = url
        end
      end

      sig {
        params(
          uri:   T.nilable(T.any(URI::Generic, String)),
          dsl:   ::Cask::DSL,
          block: T.proc.params(arg0: T.all(String, PageWithURL))
                       .returns(T.any(T.any(URI::Generic, String), [T.any(URI::Generic, String), Hash])),
        ).void
      }
      def initialize(uri, dsl:, &block)
        @uri = uri
        @dsl = dsl
        @block = block

        odeprecated "cask `url do` blocks" if @block
      end

      sig { returns(T.any(T.any(URI::Generic, String), [T.any(URI::Generic, String), Hash])) }
      def call
        if @uri
          result = ::Utils::Curl.curl_output("--fail", "--silent", "--location", @uri.to_s)
          result.assert_success!

          page = PageWithURL.new(result.stdout, URI(@uri))
          instance_exec(page, &@block)
        else
          instance_exec(&@block)
        end
      end

      private

      # Allows calling a nested `url` stanza in a `url do` block.
      #
      # @api public
      sig {
        params(
          uri:   T.any(URI::Generic, String),
          block: T.proc.params(arg0: T.all(String, PageWithURL))
                       .returns(T.any(T.any(URI::Generic, String), [T.any(URI::Generic, String), Hash])),
        ).returns(T.any(T.any(URI::Generic, String), [T.any(URI::Generic, String), Hash]))
      }
      def url(uri, &block)
        self.class.new(uri, dsl: @dsl, &block).call
      end

      # This allows calling DSL methods from inside a `url` block.
      #
      # @api public
      def method_missing(method, *args, &block)
        if @dsl.respond_to?(method)
          @dsl.public_send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_all)
        @dsl.respond_to?(method, include_all) || super
      end
    end

    sig {
      params(
        uri:             T.nilable(T.any(URI::Generic, String)),
        verified:        T.nilable(String),
        using:           T.any(Class, Symbol, NilClass),
        tag:             T.nilable(String),
        branch:          T.nilable(String),
        revisions:       T.nilable(T::Array[String]),
        revision:        T.nilable(String),
        trust_cert:      T.nilable(T::Boolean),
        cookies:         T.nilable(T::Hash[String, String]),
        referer:         T.nilable(T.any(URI::Generic, String)),
        header:          T.nilable(T.any(String, T::Array[String])),
        user_agent:      T.nilable(T.any(Symbol, String)),
        data:            T.nilable(T::Hash[String, String]),
        only_path:       T.nilable(String),
        caller_location: Thread::Backtrace::Location,
        dsl:             T.nilable(::Cask::DSL),
        block:           T.nilable(
          T.proc.params(arg0: T.all(String, BlockDSL::PageWithURL))
                .returns(T.any(T.any(URI::Generic, String), [T.any(URI::Generic, String), Hash])),
        ),
      ).void
    }
    def initialize(
      uri = nil,
      verified: nil,
      using: nil,
      tag: nil,
      branch: nil,
      revisions: nil,
      revision: nil,
      trust_cert: nil,
      cookies: nil,
      referer: nil,
      header: nil,
      user_agent: nil,
      data: nil,
      only_path: nil,
      caller_location: T.must(caller_locations).fetch(0),
      dsl: nil,
      &block
    )
      super(
        if block
          LazyObject.new do
            uri2, options = *BlockDSL.new(uri, dsl: T.must(dsl), &block).call
            options ||= {}
            DSL.new(uri2, **options)
          end
        else
          DSL.new(
            T.must(uri),
            verified:,
            using:,
            tag:,
            branch:,
            revisions:,
            revision:,
            trust_cert:,
            cookies:,
            referer:,
            header:,
            user_agent:,
            data:,
            only_path:,
          )
        end
      )

      @from_block = !block.nil?
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

    sig { returns(T::Boolean) }
    def from_block?
      @from_block
    end

    private

    sig { returns(T.nilable(String)) }
    def raw_url_line
      return @raw_url_line if defined?(@raw_url_line)

      @raw_url_line = Pathname(T.must(@caller_location.path))
                      .each_line
                      .drop(@caller_location.lineno - 1)
                      .first
    end
  end
end
