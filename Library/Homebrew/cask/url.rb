# typed: strict
# frozen_string_literal: true

require "source_location"
require "utils/curl"

module Cask
  # Class corresponding to the `url` stanza.
  class URL < SimpleDelegator
    BlockReturn = T.type_alias do
      T.any(URI::Generic, String, [T.any(URI::Generic, String), T::Hash[Symbol, T.untyped]])
    end

    class DSL
      sig { returns(T.any(URI::Generic, String)) }
      attr_reader :uri

      sig { returns(T.nilable(T::Array[String])) }
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

      sig { returns(T.any(T::Class[AbstractDownloadStrategy], Symbol, NilClass)) }
      attr_reader :using

      sig { returns(T.nilable(String)) }
      attr_reader :tag, :branch, :revision, :only_path, :verified

      extend Forwardable
      def_delegators :uri, :path, :scheme, :to_s

      sig {
        params(
          uri:        T.any(URI::Generic, String),
          # @api public
          verified:   T.nilable(String),
          # @api public
          using:      T.any(T::Class[AbstractDownloadStrategy], Symbol, NilClass),
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
        uri, verified: nil, using: nil, tag: nil, branch: nil, revisions: nil, revision: nil, trust_cert: nil,
        cookies: nil, referer: nil, header: nil, user_agent: nil, data: nil, only_path: nil
      )
        @uri = T.let(URI(uri), T.any(URI::Generic, String))

        header = Array(header) unless header.nil?

        specs = {}
        specs[:verified]   = @verified   = T.let(verified, T.nilable(String))
        specs[:using]      = @using      = T.let(using, T.any(T::Class[AbstractDownloadStrategy], Symbol, NilClass))
        specs[:tag]        = @tag        = T.let(tag, T.nilable(String))
        specs[:branch]     = @branch     = T.let(branch, T.nilable(String))
        specs[:revisions]  = @revisions  = T.let(revisions, T.nilable(T::Array[String]))
        specs[:revision]   = @revision   = T.let(revision, T.nilable(String))
        specs[:trust_cert] = @trust_cert = T.let(trust_cert, T.nilable(T::Boolean))
        specs[:cookies]    = @cookies    = T.let(cookies, T.nilable(T::Hash[String, String]))
        specs[:referer]    = @referer    = T.let(referer, T.nilable(T.any(URI::Generic, String)))
        specs[:headers]    = @header     = T.let(header, T.nilable(T.any(String, T::Array[String])))
        specs[:user_agent] = @user_agent = T.let(user_agent || :default, T.nilable(T.any(Symbol, String)))
        specs[:data]       = @data       = T.let(data, T.nilable(T::Hash[String, String]))
        specs[:only_path]  = @only_path  = T.let(only_path, T.nilable(String))

        @specs = T.let(specs.compact, T::Hash[Symbol, T.untyped])
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

        sig { params(str: String, url: URI::Generic).void }
        def initialize(str, url)
          super(str)
          @url = T.let(url, URI::Generic)
        end
      end

      sig {
        params(
          uri:   T.nilable(T.any(URI::Generic, String)),
          dsl:   ::Cask::DSL,
          block: T.proc.params(arg0: T.all(String, PageWithURL)).returns(BlockReturn),
        ).void
      }
      def initialize(uri, dsl:, &block)
        @uri = T.let(uri, T.nilable(T.any(URI::Generic, String)))
        @dsl = T.let(dsl, ::Cask::DSL)
        @block = T.let(block, T.proc.params(arg0: T.all(String, PageWithURL)).returns(BlockReturn))

        odisabled "cask `url do` blocks" if @block
      end

      sig { returns(BlockReturn) }
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
          block: T.proc.params(arg0: T.all(String, PageWithURL)).returns(BlockReturn),
        ).returns(BlockReturn)
      }
      def url(uri, &block)
        self.class.new(uri, dsl: @dsl, &block).call
      end

      # This allows calling DSL methods from inside a `url` block.
      #
      # @api public
      sig {
        override.params(method: Symbol, args: T.untyped, block: T.nilable(T.proc.returns(T.untyped)))
                .returns(T.anything)
      }
      def method_missing(method, *args, &block)
        if @dsl.respond_to?(method)
          @dsl.public_send(method, *args, &block)
        else
          super
        end
      end

      sig { override.params(method_name: T.any(Symbol, String), include_private: T::Boolean).returns(T::Boolean) }
      def respond_to_missing?(method_name, include_private = false)
        @dsl.respond_to?(method_name, include_private) || super
      end
    end

    sig {
      params(
        uri:             T.nilable(T.any(URI::Generic, String)),
        verified:        T.nilable(String),
        using:           T.any(T::Class[AbstractDownloadStrategy], Symbol, NilClass),
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
        block:           T.nilable(T.proc.params(arg0: T.all(String, BlockDSL::PageWithURL)).returns(BlockReturn)),
      ).void
    }
    def initialize(
      uri = nil, verified: nil, using: nil, tag: nil, branch: nil, revisions: nil, revision: nil, trust_cert: nil,
      cookies: nil, referer: nil, header: nil, user_agent: nil, data: nil, only_path: nil,
      caller_location: caller_locations.fetch(0), dsl: nil, &block
    )
      super(
        if block
          LazyObject.new do
            uri2, options = *BlockDSL.new(uri, dsl: T.must(dsl), &block).call
            options ||= {}
            DSL.new(uri2, **options)
          end
        else
          DSL.new(T.must(uri), verified:, using:, tag:, branch:, revisions:, revision:, trust_cert:, cookies:,
          referer:, header:, user_agent:, data:, only_path:)
        end
      )

      @from_block = T.let(!block.nil?, T::Boolean)
      @caller_location = T.let(caller_location, Thread::Backtrace::Location)
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

      @raw_url_line = T.let(Pathname(T.must(@caller_location.path))
                      .each_line
                      .drop(@caller_location.lineno - 1)
                      .first, T.nilable(String))
    end
  end
end
