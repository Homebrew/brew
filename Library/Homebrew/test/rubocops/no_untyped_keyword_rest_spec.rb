# typed: strict
# frozen_string_literal: true

require "rubocops/no_untyped_keyword_rest"

RSpec.describe RuboCop::Cop::Homebrew::NoUntypedKeywordRest, :config do
  it "registers an offense for `**options` typed `T.untyped`" do
    expect_offense(<<~RUBY)
      sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
                                          ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      def curl(*args, **options)
        curl_with_workarounds(*args, **options)
      end
    RUBY
  end

  it "registers an offense in a multi-line chained `sig`" do
    expect_offense(<<~RUBY)
      sig {
        overridable.params(
          header_token: String,
          options:      T.untyped,
                        ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
          block:        T.nilable(T.proc.void),
        ).returns(Cask)
      }
      def cask(header_token, **options, &block); end
    RUBY
  end

  it "registers an offense for a definition wrapped in an access modifier" do
    expect_offense(<<~RUBY)
      sig { params(options: T.untyped).void }
                            ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      private def install(**options); end
    RUBY
  end

  it "registers an offense for a singleton method" do
    expect_offense(<<~RUBY)
      sig { params(name: String, opts: T.untyped).void }
                                       ^^^^^^^^^ Replace `**opts` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      def self.fetch(name, **opts); end
    RUBY
  end

  it "registers an offense for a `T::Sig::WithoutRuntime` signature" do
    expect_offense(<<~RUBY)
      T::Sig::WithoutRuntime.sig { params(uri: T.nilable(String), options: T.untyped).returns(T.nilable(URL)) }
                                                                           ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      def url(uri = nil, **options); end
    RUBY
  end

  it "registers an offense for a `T::Sig` signature" do
    expect_offense(<<~RUBY)
      T::Sig.sig { params(options: T.untyped).void }
                                   ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      def run(**options); end
    RUBY
  end

  it "registers an offense for a final signature" do
    expect_offense(<<~RUBY)
      sig(:final) { params(options: T.untyped).void }
                                    ^^^^^^^^^ Replace `**options` typed `T.untyped` with explicit keyword arguments so Sorbet checks them.
      def run(**options); end
    RUBY
  end

  it "does not register an offense for explicit keyword arguments" do
    expect_no_offenses(<<~RUBY)
      sig { params(args: String, secrets: T::Array[String], timeout: T.nilable(Integer)).void }
      def curl(*args, secrets: [], timeout: nil); end
    RUBY
  end

  it "does not register an offense for a keyword rest parameter with a precise type" do
    expect_no_offenses(<<~RUBY)
      sig { params(name: String, options: EntryOption).returns(T::Boolean) }
      def install!(name, **options); end
    RUBY
  end

  it "does not register an offense for a keyword rest parameter typed `T.anything`" do
    expect_no_offenses(<<~RUBY)
      sig { params(open_args: T.anything).void }
      def append_lines(**open_args); end
    RUBY
  end

  it "does not register an offense for a `T.untyped` proc parameter with the same name" do
    expect_no_offenses(<<~RUBY)
      sig { params(options: String, block: T.proc.params(options: T.untyped).void).void }
      def run(**options, &block); end
    RUBY
  end

  it "does not register an offense for another parameter typed `T.untyped`" do
    expect_no_offenses(<<~RUBY)
      sig { params(ref: T.untyped, options: String).void }
      def checkout(ref, **options); end
    RUBY
  end

  it "does not register an offense for a keyword rest parameter without a `sig`" do
    expect_no_offenses(<<~RUBY)
      def deprecate!(date: nil, **options); end
    RUBY
  end

  it "does not register an offense for `params` in a block that is not a `sig`" do
    expect_no_offenses(<<~RUBY)
      configure { params(options: T.untyped) }
      def run(**options); end
    RUBY
  end

  it "does not register an offense for an anonymous keyword rest parameter" do
    expect_no_offenses(<<~RUBY)
      sig { params(args: String).void }
      def forward(*args, **); end
    RUBY
  end

  it "does not register an offense for an untyped positional rest parameter" do
    expect_no_offenses(<<~RUBY)
      sig { params(options: T.untyped).returns(String) }
      def to_json(*options); end
    RUBY
  end
end
