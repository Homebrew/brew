# typed: false
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::FullDependencyCheck do
  subject(:cop) { described_class.new }

  context "when auditing -full dependencies in homebrew/core" do
    let(:path) { HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-core" }

    before do
      path.mkpath
      (path/"style_exceptions").mkpath
    end

    it "reports an offense when a formula depends on a -full formula" do
      expect_offense(<<~RUBY, "#{path}/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "bar-full"
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/FullDependencyCheck: Formulae in homebrew/core should not depend on `bar-full`.
        end
      RUBY
    end

    it "reports an offense when a formula uses a -full build dependency" do
      expect_offense(<<~RUBY, "#{path}/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "baz-full" => :build
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/FullDependencyCheck: Formulae in homebrew/core should not depend on `baz-full`.
        end
      RUBY
    end

    context "with an exempted formula" do
      let(:allowlist) { path/"style_exceptions/full_dependency_allowlist.json" }

      before do
        allowlist.write(["foo"].to_json)
      end

      after do
        FileUtils.rm_f allowlist
      end

      it "reports no offense depending on a -full formula" do
        expect_no_offenses(<<~RUBY, "#{path}/Formula/foo.rb")
          class Foo < Formula
            desc "foo"
            url 'https://brew.sh/foo-1.0.tgz'

            depends_on "bar-full"
          end
        RUBY
      end

      it "reports no offense using a -full build dependency" do
        expect_no_offenses(<<~RUBY, "#{path}/Formula/foo.rb")
          class Foo < Formula
            desc "foo"
            url 'https://brew.sh/foo-1.0.tgz'

            depends_on "baz-full" => :build
          end
        RUBY
      end
    end
  end

  context "when auditing outside homebrew/core" do
    it "reports no offenses for -full dependencies" do
      expect_no_offenses(<<~RUBY, "/homebrew-cask/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          depends_on "bar-full"
        end
      RUBY
    end
  end
end
