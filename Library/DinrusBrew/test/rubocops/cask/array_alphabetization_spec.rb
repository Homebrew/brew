# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::ArrayAlphabetization, :config do
  it "reports an offense when a single `zap trash` path is specified in an array" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: ["~/Library/Application Support/Foo"]
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid single-element arrays by removing the []
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: "~/Library/Application Support/Foo"
      end
    CASK
  end

  it "reports an offense when the `zap` stanza paths are not in alphabetical order" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
                   ^ The array elements should be ordered alphabetically
          "/Library/Application Support/Foo",
          "/Library/Application Support/Baz",
          "~/Library/Application Support/Foo",
          "~/.dotfiles/thing",
          "~/Library/Application Support/Bar",
        ],
        rmdir: [
               ^ The array elements should be ordered alphabetically
          "/Applications/foo/nested/blah",
          "/Applications/foo/",
        ]
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
          "/Library/Application Support/Baz",
          "/Library/Application Support/Foo",
          "~/.dotfiles/thing",
          "~/Library/Application Support/Bar",
          "~/Library/Application Support/Foo",
        ],
        rmdir: [
          "/Applications/foo/",
          "/Applications/foo/nested/blah",
        ]
      end
    CASK
  end

  it "autocorrects alphabetization in zap trash paths with interpolation" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
                   ^ The array elements should be ordered alphabetically
          "~/Library/Application Support/Foo",
          "~/Library/Application Support/Bar\#{version.major}",
        ]
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
          "~/Library/Application Support/Bar\#{version.major}",
          "~/Library/Application Support/Foo",
        ]
      end
    CASK
  end

  it "autocorrects alphabetization in `uninstall` methods" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall pkgutil: [
                           ^ The array elements should be ordered alphabetically
          "something",
          "other",
        ],
        script: [
          "ordered",
          "differently",
        ]
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall pkgutil: [
          "other",
          "something",
        ],
        script: [
          "ordered",
          "differently",
        ]
      end
    CASK
  end

  it "ignores `uninstall` methods with commands" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall script: {
          args: ["--mode=something", "--another-mode"],
          executable: "thing",
        }
      end
    CASK
  end

  it "moves comments when autocorrecting" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
                   ^ The array elements should be ordered alphabetically
          # comment related to foo
          "~/Library/Application Support/Foo",
          # a really long comment related to Zoo
          # and the Zoo comment continues
          "~/Library/Application Support/Zoo",
          "~/Library/Application Support/Bar",
          "~/Library/Application Support/Baz", # in-line comment
        ]
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: [
          "~/Library/Application Support/Bar",
          "~/Library/Application Support/Baz", # in-line comment
          # comment related to foo
          "~/Library/Application Support/Foo",
          # a really long comment related to Zoo
          # and the Zoo comment continues
          "~/Library/Application Support/Zoo",
        ]
      end
    CASK
  end
end
