# typed: false
# frozen_string_literal: true

require "rubocops/urls"

RSpec.describe RuboCop::Cop::FormulaAudit::HttpUrls do
  subject(:cop) { described_class.new }

  context "when auditing HTTP URLs" do
    it "reports an offense for http:// URLs in homebrew-core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/HttpUrls: Formulae in homebrew/core should not use http:// URLs
        end
      RUBY
    end

    it "autocorrects http:// to https:// in homebrew-core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/HttpUrls: Formulae in homebrew/core should not use http:// URLs
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"
        end
      RUBY
    end

    it "reports no offense for http:// URLs outside homebrew-core" do
      expect_no_offenses(<<~RUBY, "/homebrew-mytap/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
        end
      RUBY
    end

    it "reports no offense for http:// mirror URLs (mirrors may use HTTP for bootstrapping)" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"
          mirror "http://mirror.example.com/foo-1.0.tar.gz"
        end
      RUBY
    end

    it "reports no offense for deprecated formulae" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
          deprecate! date: "2024-01-01", because: :unmaintained
        end
      RUBY
    end

    it "reports no offense for disabled formulae" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
          disable! date: "2024-01-01", because: :unmaintained
        end
      RUBY
    end

    it "reports no offense for http:// livecheck URLs" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"

          livecheck do
            url "http://example.com/releases"
            regex(/foo[._-]v?(\d+(?:.\d+)+).t/i)
          end

          resource "foo" do
            url "https://example.com/foo-resource-1.0.tar.gz"

            livecheck do
              url "http://example.com/resource-releases"
              regex(/foo-resource[._-]v?(\d+(?:.\d+)+).t/i)
            end
          end
        end
      RUBY
    end

    it "reports no offense for a livecheck URL symbol" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"

          livecheck do
            url :stable
          end
        end
      RUBY
    end

    it "reports no offense when livecheck has no URL" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"

          # No URL is present when `skip` is used.
          livecheck do
            skip "No version information available"
          end
        end
      RUBY
    end

    it "reports no offense when livecheck has a `url` call with no argument" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "https://example.com/foo-1.0.tar.gz"

          # This shouldn't ever happen but this is simply to exercise a guard.
          livecheck do
            url
          end
        end
      RUBY
    end

    it "reports offense for non-livecheck http:// URLs even when livecheck has http://" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url "http://example.com/foo-1.0.tar.gz"
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/HttpUrls: Formulae in homebrew/core should not use http:// URLs

          livecheck do
            url "http://example.com/releases"
            regex(/foo[._-]v?(\d+(?:.\d+)+).t/i)
          end
        end
      RUBY
    end
  end
end
