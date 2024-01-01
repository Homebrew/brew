# frozen_string_literal: true

require "rubocops/class"

describe RuboCop::Cop::FormulaAudit::ClassName do
  subject(:cop) { described_class.new }

  corrected_source = <<~RUBY
    class Foo < Formula
      url 'https://brew.sh/foo-1.0.tgz'
    end
  RUBY

  it "reports and corrects an offense when using ScriptFileFormula" do
    expect_offense(<<~RUBY)
      class Foo < ScriptFileFormula
                  ^^^^^^^^^^^^^^^^^ FormulaAudit/ClassName: ScriptFileFormula is deprecated, use Formula instead
        url 'https://brew.sh/foo-1.0.tgz'
      end
    RUBY
    expect_correction(corrected_source)
  end

  it "reports and corrects an offense when using GithubGistFormula" do
    expect_offense(<<~RUBY)
      class Foo < GithubGistFormula
                  ^^^^^^^^^^^^^^^^^ FormulaAudit/ClassName: GithubGistFormula is deprecated, use Formula instead
        url 'https://brew.sh/foo-1.0.tgz'
      end
    RUBY
    expect_correction(corrected_source)
  end

  it "reports and corrects an offense when using AmazonWebServicesFormula" do
    expect_offense(<<~RUBY)
      class Foo < AmazonWebServicesFormula
                  ^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ClassName: AmazonWebServicesFormula is deprecated, use Formula instead
        url 'https://brew.sh/foo-1.0.tgz'
      end
    RUBY
    expect_correction(corrected_source)
  end
end
