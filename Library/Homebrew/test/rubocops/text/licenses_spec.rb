# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit::Licenses do
  subject(:cop) { described_class.new }

  context "when auditing licenses" do
    it "reports no offenses for license strings" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license "MIT"
        end
      RUBY
    end

    it "reports no offenses for license symbols" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license :public_domain
        end
      RUBY
    end

    it "reports no offenses for license hashes" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: ["MIT", "0BSD"]
        end
      RUBY
    end

    it "reports no offenses for license exceptions" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license "MIT" => { with: "LLVM-exception" }
        end
      RUBY
    end

    it "reports no offenses for multiline nested license hashes" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: [
            "MIT",
            all_of: ["0BSD", "Zlib"],
          ]
        end
      RUBY
    end

    it "reports no offenses for multiline nested license hashes with exceptions" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: [
            "MIT",
            all_of: ["0BSD", "Zlib"],
            "GPL-2.0-only" => { with: "LLVM-exception" },
          ]
        end
      RUBY
    end

    it "reports an offense for nested license hashes on a single line" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          license any_of: ["MIT", all_of: ["0BSD", "Zlib"]]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Licenses: Split nested license declarations onto multiple lines
        end
      RUBY
    end
  end
end
