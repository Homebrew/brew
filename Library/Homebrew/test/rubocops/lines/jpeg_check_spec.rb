# typed: true
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::JpegCheck do
  subject(:cop) { described_class.new }

  context "when auditing jpeg dependencies in homebrew/core" do
    it "reports and corrects an offense when a formula depends on `jpeg`" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url "https://brew.sh/foo-1.0.tgz"

          depends_on "jpeg"
          ^^^^^^^^^^^^^^^^^ FormulaAudit/JpegCheck: Formulae in homebrew/core should use `depends_on "jpeg-turbo"` instead of `depends_on "jpeg"`.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://brew.sh/foo-1.0.tgz"

          depends_on "jpeg-turbo"
        end
      RUBY
    end
  end
end
