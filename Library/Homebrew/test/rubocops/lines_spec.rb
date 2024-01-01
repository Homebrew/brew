# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit::Lines do
  subject(:cop) { described_class.new }

  context "when auditing deprecated special dependencies" do
    it "reports an offense when using depends_on :automake" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on :automake
          ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Lines: :automake is deprecated. Usage should be "automake".
        end
      RUBY
    end

    it "reports an offense when using depends_on :autoconf" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on :autoconf
          ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Lines: :autoconf is deprecated. Usage should be "autoconf".
        end
      RUBY
    end

    it "reports an offense when using depends_on :libtool" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on :libtool
          ^^^^^^^^^^^^^^^^^^^ FormulaAudit/Lines: :libtool is deprecated. Usage should be "libtool".
        end
      RUBY
    end

    it "reports an offense when using depends_on :apr" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on :apr
          ^^^^^^^^^^^^^^^ FormulaAudit/Lines: :apr is deprecated. Usage should be "apr-util".
        end
      RUBY
    end

    it "reports an offense when using depends_on :tex" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on :tex
          ^^^^^^^^^^^^^^^ FormulaAudit/Lines: :tex is deprecated.
        end
      RUBY
    end
  end
end
