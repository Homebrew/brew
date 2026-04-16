# typed: false
# frozen_string_literal: true

require "rubocops/non_public_api_usage"

RSpec.describe RuboCop::Cop::FormulaAudit::NonPublicApiUsage do
  subject(:cop) { described_class.new }

  before do
    allow(RuboCop::Cop::ApiAnnotationHelper).to receive(:methods_with_api_level).and_return(Set.new)
    allow(RuboCop::Cop::ApiAnnotationHelper).to receive(:methods_with_api_level)
      .with(a_string_ending_with("formula.rb"), "internal")
      .and_return(Set["tap", "stable", "recursive_dependencies"])
    allow(RuboCop::Cop::ApiAnnotationHelper).to receive(:methods_with_api_level)
      .with(a_string_ending_with("formula.rb"), "private")
      .and_return(Set["skip_cxxstdlib_check"])
  end

  context "when auditing a formula in homebrew-core" do
    it "reports an offense for using `tap` (an @api internal method)" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/f/foo.rb")
        class Foo < Formula
          def install
            puts tap
                 ^^^ FormulaAudit/NonPublicApiUsage: Do not use `tap` in official tap formulae; it is an internal API (`@api internal`).
          end
        end
      RUBY
    end

    it "reports an offense for using `stable` (an @api internal method)" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/f/foo.rb")
        class Foo < Formula
          def install
            puts stable
                 ^^^^^^ FormulaAudit/NonPublicApiUsage: Do not use `stable` in official tap formulae; it is an internal API (`@api internal`).
          end
        end
      RUBY
    end

    it "does not report an offense for using `bin` (an @api public method)" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/f/foo.rb")
        class Foo < Formula
          def install
            bin.install "foo"
          end
        end
      RUBY
    end

    it "does not report an offense for using `prefix` (an @api public method)" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/f/foo.rb")
        class Foo < Formula
          def install
            prefix.install "README"
          end
        end
      RUBY
    end

    it "does not flag method calls on non-Formula receivers" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/f/foo.rb")
        class Foo < Formula
          def install
            something.tap { |x| x }
          end
        end
      RUBY
    end
  end

  context "when auditing a formula in a non-official tap" do
    it "does not report an offense for using internal methods" do
      expect_no_offenses(<<~RUBY, "/homebrew-mytap/Formula/foo.rb")
        class Foo < Formula
          def install
            puts tap
          end
        end
      RUBY
    end
  end
end
