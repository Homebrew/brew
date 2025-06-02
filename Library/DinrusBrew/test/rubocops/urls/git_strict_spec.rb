# frozen_string_literal: true

require "rubocops/urls"

RSpec.describe RuboCop::Cop::FormulaAuditStrict::GitUrls do
  subject(:cop) { described_class.new }

  context "when a git URL is used" do
    it "reports no offenses with both a tag and a revision" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git",
              tag:      "v1.0.0",
              revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        end
      RUBY
    end

    it "reports no offenses with both a tag, revision and `shallow` before" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git",
              shallow:  false,
              tag:      "v1.0.0",
              revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        end
      RUBY
    end

    it "reports no offenses with both a tag, revision and `shallow` after" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git",
              tag:      "v1.0.0",
              revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              shallow:  false
        end
      RUBY
    end

    it "reports an offense with no `tag`" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git",
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/GitUrls: Formulae in homebrew/core should specify a tag for git URLs
              revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        end
      RUBY
    end

    it "reports an offense with no `tag` and `shallow`" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git",
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/GitUrls: Formulae in homebrew/core should specify a tag for git URLs
              revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              shallow:  false
        end
      RUBY
    end

    it "reports no offenses with missing arguments in `head`" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://foo.com"
          head do
            url "https://github.com/foo/bar.git"
          end
        end
      RUBY
    end

    it "reports no offenses for non-core taps" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://github.com/foo/bar.git"
        end
      RUBY
    end
  end
end
