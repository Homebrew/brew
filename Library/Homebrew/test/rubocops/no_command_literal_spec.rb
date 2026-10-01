# typed: strict
# frozen_string_literal: true

require "rubocops/no_command_literal"

RSpec.describe RuboCop::Cop::Homebrew::NoCommandLiteral, :config do
  it "reports backticks" do
    expect_offense(<<~RUBY)
      output = `git status`
               ^^^^^^^^^^^^ #{RuboCop::Cop::Homebrew::NoCommandLiteral::MSG}
    RUBY
  end

  it "reports `%x`" do
    expect_offense(<<~RUBY)
      output = %x(git status)
               ^^^^^^^^^^^^^^ #{RuboCop::Cop::Homebrew::NoCommandLiteral::MSG}
    RUBY
  end

  it "reports a command heredoc" do
    expect_offense(<<~RUBY)
      output = <<~`COMMAND`
               ^^^^^^^^^^^^ #{RuboCop::Cop::Homebrew::NoCommandLiteral::MSG}
        git status
      COMMAND
    RUBY
  end

  it "reports a direct call to the backtick method" do
    expect_offense(<<~RUBY)
      output = Kernel.`("git status")
               ^^^^^^^^^^^^^^^^^^^^^^ #{RuboCop::Cop::Homebrew::NoCommandLiteral::MSG}
    RUBY
  end
end
