# typed: true
# frozen_string_literal: true

require "rubocops/move_to_extend_os"

RSpec.describe RuboCop::Cop::Homebrew::MoveToExtendOS do
  subject(:cop) { described_class.new }

  it "registers an offense when using `OS.linux?`" do
    expect_offense(<<~RUBY)
      OS.linux?
      ^^^^^^^^^ Homebrew/MoveToExtendOS: Move `OS.linux?` and `OS.mac?` calls to `extend/os`.
    RUBY
  end

  it "registers an offense when using `OS.mac?`" do
    expect_offense(<<~RUBY)
      OS.mac?
      ^^^^^^^ Homebrew/MoveToExtendOS: Move `OS.linux?` and `OS.mac?` calls to `extend/os`.
    RUBY
  end

  context "when in extend/os/mac" do
    it "registers an offense when using `OS.linux?`" do
      expect_offense(<<~RUBY, "Library/Homebrew/extend/os/mac/foo.rb")
        OS.linux?
        ^^^^^^^^^ Homebrew/MoveToExtendOS: Don't use `OS.linux?` in `extend/os/mac`, it is always `false`.
      RUBY
    end

    it "registers an offense when using `OS.mac?`" do
      expect_offense(<<~RUBY, "Library/Homebrew/extend/os/mac/foo.rb")
        OS.mac?
        ^^^^^^^ Homebrew/MoveToExtendOS: Don't use `OS.mac?` in `extend/os/mac`, it is always `true`.
      RUBY
    end
  end

  context "when in extend/os/linux" do
    it "registers an offense when using `OS.mac?`" do
      expect_offense(<<~RUBY, "Library/Homebrew/extend/os/linux/foo.rb")
        OS.mac?
        ^^^^^^^ Homebrew/MoveToExtendOS: Don't use `OS.mac?` in `extend/os/linux`, it is always `false`.
      RUBY
    end

    it "registers an offense when using `OS.linux?`" do
      expect_offense(<<~RUBY, "Library/Homebrew/extend/os/linux/foo.rb")
        OS.linux?
        ^^^^^^^^^ Homebrew/MoveToExtendOS: Don't use `OS.linux?` in `extend/os/linux`, it is always `true`.
      RUBY
    end
  end
end
