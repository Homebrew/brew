# typed: strict
# frozen_string_literal: true

require "rubocops/lines/make_check"

RSpec.describe RuboCop::Cop::FormulaAuditStrict::MakeCheck do
  sig { returns(RuboCop::Cop::FormulaAuditStrict::MakeCheck) }
  subject(:cop) { described_class.new }

  sig { returns(Pathname) }
  let(:path) { HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-core" }

  before do
    path.mkpath
    (path/"style_exceptions").mkpath
    (path/"style_exceptions/make_check_allowlist.json").write <<~JSON
      [ "bar" ]
    JSON
  end

  it "reports an offense when formulae in homebrew/core run build-time checks" do
    expect_offense(<<~RUBY, "#{path}/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        url "https://brew.sh/foo-1.0.tgz"
        def fetch
          system "make", "-j1", "test"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/MakeCheck: Formulae in homebrew/core (except e.g. cryptography, libraries) should not run build-time checks
        end
        def install
          system "gmake", "checks"
          ^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/MakeCheck: Formulae in homebrew/core (except e.g. cryptography, libraries) should not run build-time checks
          system "ctest", "--test-dir", "build"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/MakeCheck: Formulae in homebrew/core (except e.g. cryptography, libraries) should not run build-time checks
          if build.bottle?
            system "meson", "test", "-C", "build"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/MakeCheck: Formulae in homebrew/core (except e.g. cryptography, libraries) should not run build-time checks
          end
        end
      end
    RUBY
  end

  it "reports no offenses when exempted formulae in homebrew/core run build-time checks" do
    expect_no_offenses(<<~RUBY, "#{path}/Formula/bar.rb")
      class Bar < Formula
        desc "bar"
        url "https://brew.sh/bar-1.0.tgz"
        def fetch
          system "make", "-j1", "test"
        end
        def install
          system "gmake", "checks"
          system "ctest", "--test-dir", "build"
          if build.bottle?
            system "meson", "test", "-C", "build"
          end
        end
      end
    RUBY
  end

  it "reuses style exceptions across formulae in the same tap" do
    allow(Pathname).to receive(:glob).and_call_original
    expect(Pathname).to receive(:glob).with("#{path}/style_exceptions/*.json").once.and_call_original

    2.times do
      expect_no_offenses(<<~RUBY, "#{path}/Formula/bar.rb")
        class Bar < Formula
          desc "bar"
          url "https://brew.sh/bar-1.0.tgz"
          def fetch
            system "make", "-j1", "test"
          end
          def install
            system "gmake", "checks"
            system "ctest", "--test-dir", "build"
            if build.bottle?
              system "meson", "test", "-C", "build"
            end
          end
        end
      RUBY
    end
  end
end
