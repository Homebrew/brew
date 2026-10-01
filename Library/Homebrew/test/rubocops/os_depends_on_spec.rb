# typed: strict
# frozen_string_literal: true

require "rubocops/os_depends_on"

RSpec.describe RuboCop::Cop::Homebrew::OSDependsOn, :config do
  it "autocorrects the oldest runnable macOS minimum" do
    expect_offense(<<~RUBY)
      depends_on macos: :big_sur
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_correction(<<~RUBY)
      depends_on :macos
    RUBY
  end

  it "autocorrects older macOS minima" do
    expect_offense(<<~RUBY)
      depends_on macos: :catalina
                 ^^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_correction(<<~RUBY)
      depends_on :macos
    RUBY
  end

  it "autocorrects single-element minimum arrays" do
    expect_offense(<<~RUBY)
      depends_on(macos: [:big_sur])
                 ^^^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_correction(<<~RUBY)
      depends_on(:macos)
    RUBY
  end

  it "reports redundant minima in formula OS blocks without inserting bare dependencies" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        on_macos do
          depends_on macos: :big_sur
                     ^^^^^^^^^^^^^^^ Remove the redundant minimum macOS dependency from this OS block.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "preserves architecture-specific cask requirements" do
    expect_offense(<<~RUBY)
      cask "foo" do
        on_arm do
          depends_on macos: :monterey
        end
        on_intel do
          depends_on macos: :big_sur
                     ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
        end
        depends_on :macos
        app "Foo.app"
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "foo" do
        on_arm do
          depends_on macos: :monterey
        end
        on_intel do
          depends_on :macos
        end
        depends_on :macos
        app "Foo.app"
      end
    RUBY
  end

  it "does not introduce a bare OS dependency inside a cask macOS block" do
    expect_offense(<<~RUBY)
      cask "foo" do
        on_macos do
          depends_on macos: :big_sur
                     ^^^^^^^^^^^^^^^ Remove the redundant minimum macOS dependency from this OS block.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "does not introduce a bare OS dependency inside a cask release block" do
    expect_offense(<<~RUBY)
      cask "foo" do
        on_big_sur do
          depends_on macos: :big_sur
                     ^^^^^^^^^^^^^^^ Remove the redundant minimum macOS dependency from this OS block.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "does not introduce a bare OS dependency inside a cask mixed OS block" do
    expect_offense(<<~RUBY)
      cask "foo" do
        on_system :linux, macos: :big_sur do
          depends_on macos: :big_sur
                     ^^^^^^^^^^^^^^^ Remove the redundant minimum macOS dependency from this OS block.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "does not orphan a redundant minimum comment next to a maximum" do
    expect_offense(<<~RUBY)
      depends_on macos: :big_sur # Keep this explanation.
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
      depends_on maximum_macos: :ventura
    RUBY

    expect_no_corrections
  end

  it "does not autocorrect a dependency hash with other requirements" do
    expect_offense(<<~RUBY)
      depends_on macos: :big_sur, arch: :arm64
                 ^^^^^^^^^^^^^^^ Remove the redundant `macos:` pair and add a separate `depends_on :macos`.
    RUBY

    expect_no_corrections
  end

  it "does not discard comments inside a minimum array" do
    expect_offense(<<~RUBY)
      depends_on macos: [
                 ^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
        # Keep this explanation.
        :big_sur,
      ]
    RUBY

    expect_no_corrections
  end

  it "allows meaningful version restrictions and dynamic values" do
    expect_no_offenses(<<~RUBY)
      depends_on macos: :monterey
      depends_on maximum_macos: :big_sur
      depends_on macos: [:big_sur, :monterey]
      depends_on macos: minimum_macos
      depends_on macos: :unknown
      helper.depends_on macos: :big_sur
    RUBY
  end

  it "follows changes to the runnable macOS releases" do
    stub_const("MacOSVersion::SYMBOLS", { ventura: "13", monterey: "12" })

    expect_offense(<<~RUBY)
      depends_on macos: :monterey
                 ^^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_correction(<<~RUBY)
      depends_on :macos
    RUBY
  end

  it "autocorrects legacy redundant minimum comparison strings" do
    expect_offense(<<~RUBY)
      depends_on macos: ">= :big_sur"
                        ^^^^^^^^^^^^^ Use `depends_on macos: :big_sur`.
    RUBY

    expect_correction(<<~RUBY)
      depends_on :macos
    RUBY
  end

  it "autocorrects cask macOS comparison strings" do
    expect_offense(<<~RUBY)
      depends_on macos: ">= :monterey"
                        ^^^^^^^^^^^^^^ Use `depends_on macos: :monterey`.
      depends_on macos: "<= :sonoma"
                        ^^^^^^^^^^^^ Use `depends_on maximum_macos: :sonoma`.
      depends_on maximum_macos: "<= :tahoe"
                                ^^^^^^^^^^^ Use `depends_on maximum_macos: :tahoe`.
    RUBY

    expect_correction(<<~RUBY)
      depends_on macos: :monterey
      depends_on maximum_macos: :sonoma
      depends_on maximum_macos: :tahoe
    RUBY
  end

  it "autocorrects redundant bare macOS requirements" do
    expect_offense(<<~RUBY)
      depends_on :macos
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
      depends_on macos: :monterey
    RUBY

    expect_correction(<<~RUBY)
      depends_on macos: :monterey
    RUBY
  end

  it "does not duplicate a commented bare macOS sibling before a redundant minimum" do
    expect_offense(<<~RUBY)
      depends_on :macos # Keep this explanation.
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
      depends_on macos: :big_sur
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_no_corrections
  end

  it "does not duplicate a commented bare macOS sibling after a redundant minimum" do
    expect_offense(<<~RUBY)
      depends_on macos: :big_sur
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
      depends_on :macos # Keep this explanation.
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
    RUBY

    expect_no_corrections
  end

  it "converges when an uncommented bare macOS sibling accompanies a redundant minimum" do
    expect_offense(<<~RUBY)
      depends_on :macos
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
      depends_on macos: :big_sur
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_correction(<<~RUBY)
      depends_on :macos
    RUBY
  end

  it "does not autocorrect a minimum with a trailing comment" do
    expect_offense(<<~RUBY)
      depends_on macos: :big_sur # Needs APIs introduced in Big Sur.
                 ^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
    RUBY

    expect_no_corrections
  end

  it "does not orphan a redundant bare macOS dependency comment" do
    expect_offense(<<~RUBY)
      depends_on :macos # Keep this explanation.
      ^^^^^^^^^^^^^^^^^ Remove redundant `depends_on :macos`.
      depends_on maximum_macos: :ventura
    RUBY

    expect_no_corrections
  end

  it "reports tagged formula minima without suggesting a tag-only dependency" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        depends_on macos: [:big_sur, :build]
                   ^^^^^^^^^^^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
      end
    RUBY

    expect_no_corrections
  end

  it "treats additional macOS symbols as tags in formula arrays" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        depends_on macos: [:big_sur, :monterey]
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `depends_on :macos` instead of a redundant minimum macOS version.
      end
    RUBY

    expect_no_corrections
  end

  it "keeps the oldest runnable symbol aligned with the runtime floor" do
    expect(MacOSVersion::SYMBOLS.values.map { |release| MacOSVersion.new(release) }.min)
      .to eq(MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED))
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
      depends_on macos: :monterey
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `depends_on` cannot be macOS-only and Linux-only.
      depends_on :linux
      ^^^^^^^^^^^^^^^^^ `depends_on` cannot be macOS-only and Linux-only.
    RUBY
  end

  it "allows scoped macOS requirements" do
    expect_no_offenses(<<~RUBY)
      on_macos do
        depends_on macos: :monterey
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

  it "autocorrects missing bare macOS dependencies for artifacts in architecture blocks" do
    expect_offense(<<~RUBY)
      cask "basic" do
        on_intel do
          version "1.0"
          app "Basic.app"
          ^^^^^^^^^^^^^^^ Add `depends_on :macos` for macOS-only casks.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        on_intel do
          version "1.0"
          app "Basic.app"
        end

        depends_on :macos
      end
    RUBY
  end

  it "autocorrects missing bare Linux dependencies for Linux-only cask stanzas" do
    expect_offense(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        app_image "Basic.AppImage"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ Add `depends_on :linux` for Linux-only casks.
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        version "1.0"
        sha256 "abc"
        url "https://example.com/basic.zip"
        homepage "https://example.com"

        depends_on :linux

        app_image "Basic.AppImage"
      end
    RUBY
  end

  it "autocorrects missing bare Linux dependencies using cask stanza order" do
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

        app_image "Ordered.AppImage"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Add `depends_on :linux` for Linux-only casks.
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
        depends_on :linux

        container nested: "Ordered"

        app_image "Ordered.AppImage"
      end
    RUBY
  end

  it "autocorrects missing bare Linux dependencies before Linux-only cask stanzas" do
    expect_offense(<<~RUBY)
      cask "basic" do
        version "1.0"

        app_image "Basic.AppImage"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ Add `depends_on :linux` for Linux-only casks.
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        version "1.0"

        depends_on :linux

        app_image "Basic.AppImage"
      end
    RUBY
  end

  it "autocorrects missing bare Linux dependencies for artifacts in architecture blocks" do
    expect_offense(<<~RUBY)
      cask "basic" do
        on_arm do
          version "1.0"
          app_image "Basic.AppImage"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^ Add `depends_on :linux` for Linux-only casks.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "basic" do
        on_arm do
          version "1.0"
          app_image "Basic.AppImage"
        end

        depends_on :linux
      end
    RUBY
  end

  it "requires OS scoping for architecture artifacts in cross-platform casks" do
    expect_offense(<<~RUBY)
      cask "dual-os-arch" do
        on_intel do
          app "Foo.app"
          ^^^^^^^^^^^^^ Move this macOS-only stanza into an `on_macos` block for cross-platform casks.
        end

        on_linux do
          app_image "Foo.AppImage"
        end
      end
    RUBY

    expect_no_corrections
  end

  it "requires OS scoping for top-level artifacts in cross-platform casks" do
    expect_offense(<<~RUBY)
      cask "toplevel-cross-platform" do
        app "Foo.app"
        ^^^^^^^^^^^^^ Move this macOS-only stanza into an `on_macos` block for cross-platform casks.

        on_linux do
          binary "foo"
        end
      end
    RUBY

    expect_no_corrections
  end

  it "requires OS scoping for artifacts in on_system blocks" do
    expect_offense(<<~RUBY)
      cask "on-system-artifact" do
        on_system :linux, macos: :sonoma_or_older do
          app_image "Foo.AppImage"
          ^^^^^^^^^^^^^^^^^^^^^^^^ Move this Linux-only stanza into an `on_linux` block for cross-platform casks.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "does not autocorrect conflicting OS-specific architecture artifacts" do
    expect_offense(<<~RUBY)
      cask "conflicting-arch-artifacts" do
        on_arm do
          app_image "Foo.AppImage"
          ^^^^^^^^^^^^^^^^^^^^^^^^ Move this Linux-only stanza into an `on_linux` block for cross-platform casks.
        end

        on_intel do
          app "Foo.app"
          ^^^^^^^^^^^^^ Move this macOS-only stanza into an `on_macos` block for cross-platform casks.
        end
      end
    RUBY

    expect_no_corrections
  end

  it "accepts casks without macOS-only or Linux-only stanzas" do
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

        depends_on macos: :monterey

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
          depends_on macos: :monterey
        end

        on_intel do
          depends_on :macos
        end

        app "Basic.app"
      end
    RUBY
  end
end
