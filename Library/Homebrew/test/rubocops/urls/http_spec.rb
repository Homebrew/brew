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
            regex(/foo-(\d+(?:.\d+)+).tar.gz/i)
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
            regex(/foo-(\d+(?:.\d+)+).tar.gz/i)
          end
        end
      RUBY
    end
  end
end
