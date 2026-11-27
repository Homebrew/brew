# typed: strict
# frozen_string_literal: true

require "rubocops/lines/class_inheritance"

RSpec.describe RuboCop::Cop::FormulaAudit::ClassInheritance do
  sig { returns(RuboCop::Cop::FormulaAudit::ClassInheritance) }
  subject(:cop) { described_class.new }

  context "when auditing formula class inheritance" do
    it "reports and corrects an offense when not using spaces for class inheritance" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo<Formula
                  ^^^^^^^ FormulaAudit/ClassInheritance: Use a space in class inheritance: class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
        end
      RUBY
    end
  end
end
