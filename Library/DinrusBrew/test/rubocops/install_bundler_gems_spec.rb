# frozen_string_literal: true

require "rubocops/install_bundler_gems"

RSpec.describe RuboCop::Cop::DinrusBrew::InstallBundlerGems, :config do
  it "registers an offense and corrects when using `DinrusBrew.install_bundler_gems!`" do
    expect_offense(<<~RUBY)
      DinrusBrew.install_bundler_gems!
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Only use `DinrusBrew.install_bundler_gems!` in dev-cmd.
    RUBY
  end
end
