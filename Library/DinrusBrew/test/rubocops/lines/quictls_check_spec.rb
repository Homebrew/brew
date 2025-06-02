# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::QuicTLSCheck do
  subject(:cop) { described_class.new }

  context "when auditing formula dependencies" do
    it "reports an offense when a formula depends on `quictls`" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "quictls"
          ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/QuicTLSCheck: Formulae in homebrew/core should use 'depends_on "openssl@3"' instead of 'depends_on "quictls"'.
        end
      RUBY
    end
  end
end
