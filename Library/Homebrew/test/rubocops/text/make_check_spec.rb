# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAuditStrict::MakeCheck do
  subject(:cop) { described_class.new }

  let(:path) { Tap::TAP_DIRECTORY/"homebrew/homebrew-core" }

  before do
    path.mkpath
    (path/"style_exceptions").mkpath
  end

  def setup_style_exceptions
    (path/"style_exceptions/make_check_allowlist.json").write <<~JSON
      [ "bar" ]
    JSON
  end

  it "reports an offense when formulae in homebrew/core run build-time checks" do
    setup_style_exceptions

    expect_offense(<<~RUBY, "#{path}/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        url 'https://brew.sh/foo-1.0.tgz'
        system "make", "-j1", "test"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/MakeCheck: Formulae in homebrew/core (except e.g. cryptography, libraries) should not run build-time checks
      end
    RUBY
  end

  it "reports no offenses when exempted formulae in homebrew/core run build-time checks" do
    setup_style_exceptions

    expect_no_offenses(<<~RUBY, "#{path}/Formula/bar.rb")
      class Bar < Formula
        desc "bar"
        url 'https://brew.sh/bar-1.0.tgz'
        system "make", "-j1", "test"
      end
    RUBY
  end
end
