# typed: strict
# frozen_string_literal: true

require "rubocops/os_depends_on"

RSpec.describe RuboCop::Cop::Homebrew::OSDependsOn, :config do
  it "autocorrects cask macOS comparison strings" do
    expect_offense(<<~RUBY)
      depends_on macos: ">= :catalina"
                        ^^^^^^^^^^^^^^ Use `depends_on macos: :catalina`.
      depends_on macos: "<= :sonoma"
                        ^^^^^^^^^^^^ Use `depends_on maximum_macos: :sonoma`.
      depends_on maximum_macos: "<= :tahoe"
                                ^^^^^^^^^^^ Use `depends_on maximum_macos: :tahoe`.
    RUBY

    expect_correction(<<~RUBY)
      depends_on macos: :catalina
      depends_on maximum_macos: :sonoma
      depends_on maximum_macos: :tahoe
    RUBY
  end

  it "autocorrects redundant bare macOS requirements" do
    expect_offense(<<~RUBY)
      depends_on :macos
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
      depends_on macos: :catalina
    RUBY

    expect_correction(<<~RUBY)
      depends_on macos: :catalina
    RUBY
  end

  it "ignores non-symbol dependency hash keys" do
    expect_no_offenses(<<~RUBY)
      depends_on GawkRequirement => :build
      depends_on MakeRequirement => :build
      depends_on "linux-headers@4.4" => :build
      depends_on :linux
      depends_on LinuxKernelRequirement
    RUBY
  end

  it "reports conflicting macOS-only and Linux-only requirements" do
    expect_offense(<<~RUBY)
      depends_on macos: :catalina
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `depends_on` cannot be macOS-only and Linux-only.
      depends_on :linux
      ^^^^^^^^^^^^^^^^^ `depends_on` cannot be macOS-only and Linux-only.
    RUBY
  end

  it "allows scoped macOS requirements" do
    expect_no_offenses(<<~RUBY)
      on_macos do
        depends_on macos: :catalina
      end

      depends_on :linux
    RUBY
  end

  it "autocorrects missing bare macOS dependencies for macOS-only cask stanzas" do
    expect_offense(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        app "Basic.app"
        ^^^^^^^^^^^^^^^ Add `depends_on :macos` for macOS-only casks.
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        depends_on :macos

        app "Basic.app"
      end
    RUBY
  end

  it "autocorrects missing bare macOS dependencies using cask stanza order" do
    expect_offense(<<~RUBY)
      cask "ordered" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/ordered.zip"
        name "Ordered"
        desc "Ordered"
        homepage "https://example.com"

        livecheck do
          skip "example"
        end

        auto_updates true
        conflicts_with cask: "old-ordered"
        container nested: "Ordered"

        app "Ordered.app"
        ^^^^^^^^^^^^^^^^^ Add `depends_on :macos` for macOS-only casks.
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "ordered" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/ordered.zip"
        name "Ordered"
        desc "Ordered"
        homepage "https://example.com"

        livecheck do
          skip "example"
        end

        auto_updates true
        conflicts_with cask: "old-ordered"
        depends_on :macos

        container nested: "Ordered"

        app "Ordered.app"
      end
    RUBY
  end

  it "autocorrects missing bare macOS dependencies before macOS-only cask stanzas" do
    expect_offense(<<~RUBY)
      cask "basic" do
        version "1.0"

        installer manual: "Basic.app"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Add `depends_on :macos` for macOS-only casks.
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        version "1.0"

        depends_on :macos

        installer manual: "Basic.app"
      end
    RUBY
  end

  it "accepts casks without macOS-only stanzas" do
    expect_no_offenses(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.tar.gz"
        homepage "https://example.com"

        binary "basic"
      end
    RUBY
  end

  it "accepts casks with explicit OS dependencies" do
    expect_no_offenses(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        depends_on macos: :catalina

        app "Basic.app"
      end
    RUBY
  end

  it "accepts casks with explicit OS dependencies in nested blocks" do
    expect_no_offenses(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        on_arm do
          depends_on macos: :big_sur
        end

        on_intel do
          depends_on :macos
        end

        app "Basic.app"
      end
    RUBY
  end
end
