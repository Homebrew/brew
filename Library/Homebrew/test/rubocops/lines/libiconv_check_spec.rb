# typed: false
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::LibiconvCheck do
  subject(:cop) { described_class.new }

  context "when auditing libiconv dependencies in homebrew/core" do
    it "reports an offense when a formula depends on `libiconv`" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "libiconv"
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LibiconvCheck: Formulae in homebrew/core should not use `depends_on "libiconv"`.
        end
      RUBY
    end

    it "reports no offenses for `neomutt`" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/n/neomutt.rb")
        class Neomutt < Formula
          desc "neomutt"
          url 'https://brew.sh/neomutt-1.0.tgz'

          depends_on "libiconv"
        end
      RUBY
    end
  end

  context "when auditing outside homebrew/core" do
    it "reports no offenses for libiconv dependencies" do
      expect_no_offenses(<<~RUBY, "/homebrew-cask/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "libiconv"
        end
      RUBY
    end
  end
end
