# frozen_string_literal: true

require "rubocops/install_bundler_gems"

RSpec.describe RuboCop::Cop::Homebrew::InstallBundlerGems, :config do
  it "registers an offense and corrects when using `Homebrew.install_bundler_gems!`" do
    expect_offense(<<~RUBY)
      Homebrew.install_bundler_gems!
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Only use `Homebrew.install_bundler_gems!` in dev-cmd.
    RUBY
  end
end
