# typed: true
# frozen_string_literal: true

require "rubocops/public_api_documentation"

RSpec.describe RuboCop::Cop::Homebrew::PublicApiDocumentation do
  subject(:cop) { described_class.new }

  context "when a method has a bare `@api public` with no description" do
    it "reports an offense" do
      expect_offense(<<~RUBY)
        # @api public
        ^^^^^^^^^^^^^ Homebrew/PublicApiDocumentation: `@api public` methods must have a descriptive YARD comment, not just the annotation.
        sig { returns(String) }
        def foo; end
      RUBY
    end
  end

  context "when `@api public` is preceded only by blank comment lines" do
    it "reports an offense" do
      expect_offense(<<~RUBY)
        #
        # @api public
        ^^^^^^^^^^^^^ Homebrew/PublicApiDocumentation: `@api public` methods must have a descriptive YARD comment, not just the annotation.
        sig { returns(String) }
        def foo; end
      RUBY
    end
  end

  context "when `@api public` is preceded only by other YARD tags" do
    it "reports an offense" do
      expect_offense(<<~RUBY)
        # @return [String]
        # @api public
        ^^^^^^^^^^^^^ Homebrew/PublicApiDocumentation: `@api public` methods must have a descriptive YARD comment, not just the annotation.
        sig { returns(String) }
        def foo; end
      RUBY
    end
  end

  context "when a method has a descriptive comment before `@api public`" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY)
        # The name of the formula.
        #
        # @api public
        sig { returns(String) }
        def name; end
      RUBY
    end
  end

  context "when a method has a multi-line description before `@api public`" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY)
        # The directory where the formula's binaries should be installed.
        # This is symlinked into `HOMEBREW_PREFIX` after installation.
        #
        # @api public
        sig { returns(Pathname) }
        def bin; end
      RUBY
    end
  end

  context "when there is no `@api public` annotation" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY)
        # A private method.
        sig { returns(String) }
        def foo; end
      RUBY
    end
  end

  context "when `@api public` has a description with examples" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY)
        # The installation prefix.
        #
        # ### Example
        #
        # ```ruby
        # prefix.install "file"
        # ```
        #
        # @api public
        sig { returns(Pathname) }
        def prefix; end
      RUBY
    end
  end

  context "when a public API file is missing from `Style/Documentation.Include`" do
    subject(:cop) do
      described_class.new(
        RuboCop::Config.new("Style/Documentation" => { "Include" => [] }),
      )
    end

    it "reports an offense" do
      expect_offense(<<~RUBY, "public_api.rb")
        # The public method.
        #
        # @api public
        ^^^^^^^^^^^^^ `public_api.rb` contains `@api public` but is missing from `Style/Documentation.Include`.
        def foo; end
      RUBY
    end
  end

  context "when a documented API file has no public API annotations" do
    subject(:cop) do
      described_class.new(
        RuboCop::Config.new("Style/Documentation" => { "Include" => ["stale.rb"] }),
      )
    end

    it "reports an offense" do
      expect_offense(<<~RUBY, "stale.rb")
        class Stale
        ^^^^^^^^^^^ `stale.rb` is included in `Style/Documentation.Include` but does not contain `@api public`.
        end
      RUBY
    end
  end
end
