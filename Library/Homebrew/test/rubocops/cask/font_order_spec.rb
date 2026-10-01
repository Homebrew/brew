# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::FontOrder, :config do
  it "accepts `font` stanzas in alphabetical order" do
    expect_no_offenses(<<~CASK)
      cask "font-foo" do
        font "Foo-Bold.ttf"
        font "Foo-Regular.ttf"
      end
    CASK
  end

  it "sorts `font` stanzas case-sensitively" do
    expect_no_offenses(<<~CASK)
      cask "font-foo" do
        font "Foo-Regular.ttf"
        font "foo-bold.ttf"
      end
    CASK
  end

  it "registers an offense and corrects `font` stanzas out of order" do
    expect_offense(<<~CASK)
      cask "font-foo" do
        font "Foo-Regular.ttf"
        ^^^^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
        font "Foo-Bold.ttf"
        ^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
      end
    CASK

    expect_correction(<<~CASK)
      cask "font-foo" do
        font "Foo-Bold.ttf"
        font "Foo-Regular.ttf"
      end
    CASK
  end

  it "keeps comments with their `font` stanza" do
    expect_offense(<<~CASK)
      cask "font-foo" do
        font "Foo-Regular.ttf"
        ^^^^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
        # Only shipped since 2.0.
        font "Foo-Bold.ttf"
        ^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
      end
    CASK

    expect_correction(<<~CASK)
      cask "font-foo" do
        # Only shipped since 2.0.
        font "Foo-Bold.ttf"
        font "Foo-Regular.ttf"
      end
    CASK
  end

  it "sorts `font` stanzas within `on_*` blocks separately" do
    expect_offense(<<~CASK)
      cask "font-foo" do
        on_macos do
          font "Foo-Regular.ttf"
          ^^^^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
          font "Foo-Bold.ttf"
          ^^^^^^^^^^^^^^^^^^^ `font` stanzas should be ordered alphabetically
        end
      end
    CASK

    expect_correction(<<~CASK)
      cask "font-foo" do
        on_macos do
          font "Foo-Bold.ttf"
          font "Foo-Regular.ttf"
        end
      end
    CASK
  end
end
