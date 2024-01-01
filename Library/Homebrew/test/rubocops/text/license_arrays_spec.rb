# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit::LicenseArrays do
  subject(:cop) { described_class.new }

  context "when auditing license arrays" do
    it "reports no offenses for license strings" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license "MIT"
        end
      RUBY
    end

    it "reports no offenses for license symbols" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license :public_domain
        end
      RUBY
    end

    it "reports no offenses for license hashes" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: ["MIT", "0BSD"]
        end
      RUBY
    end

    it "reports and corrects use of a license array" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license ["MIT", "0BSD"]
          ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LicenseArrays: Use `license any_of: ["MIT", "0BSD"]` instead of `license ["MIT", "0BSD"]`
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: ["MIT", "0BSD"]
        end
      RUBY
    end
  end
end
