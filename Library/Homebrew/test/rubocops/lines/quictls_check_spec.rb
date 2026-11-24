# typed: strict
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::QuicTLSCheck do
  sig { returns(RuboCop::Cop::FormulaAudit::QuicTLSCheck) }
  subject(:cop) { described_class.new }

  context "when auditing formula dependencies" do
    it "reports and corrects an offense when a formula depends on `quictls`" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "quictls" => :build
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/QuicTLSCheck: Formulae in homebrew/core should use `depends_on "openssl@4"` instead of `depends_on "quictls"`.
          depends_on "quictls"
          ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/QuicTLSCheck: Formulae in homebrew/core should use `depends_on "openssl@4"` instead of `depends_on "quictls"`.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "openssl@4" => :build
          depends_on "openssl@4"
        end
      RUBY
    end
  end
end
