# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::NoOverrides, :config do
  it "accepts when there are no `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version '1.2.3'
        url 'https://brew.sh/foo.pkg'

        name 'Foo'
      end
    CASK
  end

  it "accepts when there are no top-level standalone stanzas" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        on_mojave :or_later do
          version :latest
        end
      end
    CASK
  end

  it "accepts non-overridable stanzas in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version '1.2.3'

        on_arm do
          binary "foo-\#{version}-arm64"
        end

        app "foo-\#{version}.app"

        binary "foo-\#{version}"
      end
    CASK
  end

  it "accepts `arch` and `version` interpolations in strings in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86"
        version '1.2.3'

        on_mojave :or_later do
          sha256 "aaa"

          url "https://brew.sh/foo-\#{version}-\#{arch}.pkg"
        end
      end
    CASK
  end

  it "accepts `version` interpolations with method calls in strings in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version '0.99,123.3'

        on_mojave :or_later do
          url "https://brew.sh/foo-\#{version.csv.first}-\#{version.csv.second}.pkg"
        end
      end
    CASK
  end

  it "accepts `arch` interpolations in regexes in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86"

        version '0.99,123.3'

        on_mojave :or_later do
          url "https://brew.sh/foo-\#{arch}-\#{version.csv.first}-\#{version.csv.last}.pkg"

          livecheck do
            url "https://brew.sh/foo/releases.html"
            regex(/href=.*?foo[._-]v?(\d+(?:.\d+)+)-\#{arch}.pkg/i)
          end
        end
      end
    CASK
  end

  it "ignores contents of single-line `livecheck` blocks in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        on_intel do
          livecheck do
            url 'https://brew.sh/foo' # Livecheck should be allowed since it's a different "kind" of URL.
          end
          version '1.2.3'
        end
        on_arm do
          version '2.3.4'
        end

        url 'https://brew.sh/foo.pkg'
        sha256 "bbb"
      end
    CASK
  end

  it "ignores contents of multi-line `livecheck` blocks in `on_*` blocks" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        on_intel do
          livecheck do
            url 'https://brew.sh/foo' # Livecheck should be allowed since it's a different "kind" of URL.
            strategy :sparkle
          end
          version '1.2.3'
        end
        on_arm do
          version '2.3.4'
        end

        url 'https://brew.sh/foo.pkg'
        sha256 "bbb"
      end
    CASK
  end

  it "accepts `on_*` blocks that don't override upper-level stanzas" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version "1.2.3"

        on_big_sur :or_older do
          sha256 "bbb"
          url "https://brew.sh/legacy/foo-2.3.4.dmg"
        end
        on_monterey :or_newer do
          sha256 "aaa"
          url "https://brew.sh/foo-2.3.4.dmg"
        end
      end
    CASK
  end

  it "reports an offense when `on_*` blocks override a single upper-level stanza" do
    expect_offense <<~CASK
      cask 'foo' do
        version '2.3.4'
        ^^^^^^^^^^^^^^^ Do not use a top-level `version` stanza as the default. Add it to an `on_{system}` block instead. Use `:or_older` or `:or_newer` to specify a range of macOS versions.

        on_mojave :or_older do
          version '1.2.3'
        end

        url 'https://brew.sh/foo-2.3.4.dmg'
      end
    CASK
  end

  it "reports an offense when `on_*` blocks override multiple upper-level stanzas" do
    expect_offense <<~CASK
      cask "foo" do
        version "1.2.3"
        sha256 "aaa"
        ^^^^^^^^^^^^ Do not use a top-level `sha256` stanza as the default. Add it to an `on_{system}` block instead. Use `:or_older` or `:or_newer` to specify a range of macOS versions.
        url "https://brew.sh/foo-2.3.4.dmg"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not use a top-level `url` stanza as the default. Add it to an `on_{system}` block instead. Use `:or_older` or `:or_newer` to specify a range of macOS versions.

        on_big_sur :or_older do
          sha256 "bbb"
          url "https://brew.sh/legacy/foo-2.3.4.dmg"
        end
      end
    CASK
  end
end
