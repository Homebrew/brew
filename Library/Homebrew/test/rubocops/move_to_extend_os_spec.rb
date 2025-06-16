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
end
