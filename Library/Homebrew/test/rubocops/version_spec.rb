# frozen_string_literal: true

require "rubocops/version"

describe RuboCop::Cop::FormulaAudit::Version do
  subject(:cop) { described_class.new }

  context "when auditing version" do
    it "reports an offense if `version` is an empty string" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          version ""
          ^^^^^^^^^^ FormulaAudit/Version: version is set to an empty string
        end
      RUBY
    end

    it "reports an offense if `version` has a leading 'v'" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          version "v1.0"
          ^^^^^^^^^^^^^^ FormulaAudit/Version: version v1.0 should not have a leading 'v'
        end
      RUBY
    end

    it "reports an offense if `version` ends with an underline and a number" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          version "1_0"
          ^^^^^^^^^^^^^ FormulaAudit/Version: version 1_0 should not end with an underline and a number
        end
      RUBY
    end
  end
end
