# frozen_string_literal: true

require "rubocops/zero_zero_zero_zero"

RSpec.describe RuboCop::Cop::FormulaAudit::ZeroZeroZeroZero do
  subject(:cop) { described_class.new }

  it "reports no offenses when 0.0.0.0 is used inside test do blocks" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        test do
          system "echo", "0.0.0.0"
        end
      end
    RUBY
  end

  it "reports no offenses for valid IP ranges like 10.0.0.0" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def install
          system "echo", "10.0.0.0"
        end
      end
    RUBY
  end

  it "reports no offenses for IP range notation like 0.0.0.0-255.255.255.255" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def install
          system "echo", "0.0.0.0-255.255.255.255"
        end
      end
    RUBY
  end

  it "reports no offenses for private IP ranges" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def install
          system "echo", "192.168.1.1"
          system "echo", "172.16.0.1"
          system "echo", "10.0.0.1"
        end
      end
    RUBY
  end

  it "reports no offenses when outside of homebrew-core" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        service do
          run [bin/"foo", "--host", "0.0.0.0"]
        end
      end
    RUBY
  end

  it "reports offenses when 0.0.0.0 is used in service blocks" do
    expect_offense(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        service do
          run [bin/"foo", "--host", "0.0.0.0"]
                                    ^^^^^^^^^ FormulaAudit/ZeroZeroZeroZero: Do not use 0.0.0.0 as it can be a security risk.
        end
      end
    RUBY
  end

  it "reports offenses when 0.0.0.0 is used outside of test do blocks" do
    expect_offense(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def install
          system "echo", "0.0.0.0"
                         ^^^^^^^^^ FormulaAudit/ZeroZeroZeroZero: Do not use 0.0.0.0 as it can be a security risk.
        end
      end
    RUBY
  end

  it "reports offenses for 0.0.0.0 in method definitions outside test blocks" do
    expect_offense(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def configure
          system "./configure", "--bind-address=0.0.0.0"
                                ^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ZeroZeroZeroZero: Do not use 0.0.0.0 as it can be a security risk.
        end
      end
    RUBY
  end

  it "reports multiple offenses when 0.0.0.0 is used in multiple places" do
    expect_offense(<<~RUBY, "/homebrew-core/")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        desc "A test formula"

        def install
          system "echo", "0.0.0.0"
                         ^^^^^^^^^ FormulaAudit/ZeroZeroZeroZero: Do not use 0.0.0.0 as it can be a security risk.
        end

        def post_install
          system "echo", "0.0.0.0"
                         ^^^^^^^^^ FormulaAudit/ZeroZeroZeroZero: Do not use 0.0.0.0 as it can be a security risk.
        end
      end
    RUBY
  end
end
