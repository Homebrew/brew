# frozen_string_literal: true

require "rubocops/urls"

RSpec.describe RuboCop::Cop::FormulaAudit::PyPiUrls do
  subject(:cop) { described_class.new }

  context "when a pypi URL is used" do
    it "reports an offense for pypi.python.org urls" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://pypi.python.org/packages/source/foo/foo-0.1.tar.gz"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/PyPiUrls: use the `Source` url found on PyPI downloads page (`https://pypi.org/project/foo/#files`)
        end
      RUBY
    end

    it "reports an offense for short file.pythonhosted.org urls" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://files.pythonhosted.org/packages/source/f/foo/foo-0.1.tar.gz"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/PyPiUrls: use the `Source` url found on PyPI downloads page (`https://pypi.org/project/foo/#files`)
        end
      RUBY
    end

    it "reports no offenses for long file.pythonhosted.org urls" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://files.pythonhosted.org/packages/a0/b1/a01b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f/foo-0.1.tar.gz"
        end
      RUBY
    end
  end
end
