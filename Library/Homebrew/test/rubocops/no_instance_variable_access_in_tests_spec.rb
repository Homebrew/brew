# typed: strict
# frozen_string_literal: true

require "rubocops/no_instance_variable_access_in_tests"

RSpec.describe RuboCop::Cop::Homebrew::NoInstanceVariableAccessInTests, :config do
  it "registers an offense when using `instance_variable_get`" do
    expect_offense(<<~RUBY)
      formula.instance_variable_get(:@tap)
              ^^^^^^^^^^^^^^^^^^^^^ Use a public `attr_reader`/`attr_writer` (or an existing accessor) instead of `instance_variable_get` in tests.
    RUBY
  end

  it "registers an offense when using `instance_variable_set`" do
    expect_offense(<<~RUBY)
      formula.instance_variable_set(:@tap, CoreTap.instance)
              ^^^^^^^^^^^^^^^^^^^^^ Use a public `attr_reader`/`attr_writer` (or an existing accessor) instead of `instance_variable_set` in tests.
    RUBY
  end

  it "registers an offense when using `instance_variable_set` without a receiver" do
    expect_offense(<<~RUBY)
      instance_variable_set(:@staged_path, tmp_staged)
      ^^^^^^^^^^^^^^^^^^^^^ Use a public `attr_reader`/`attr_writer` (or an existing accessor) instead of `instance_variable_set` in tests.
    RUBY
  end

  it "registers an offense when using `instance_variable_get` with a dynamic name" do
    expect_offense(<<~RUBY)
      pathname.instance_variable_get(ivar)
               ^^^^^^^^^^^^^^^^^^^^^ Use a public `attr_reader`/`attr_writer` (or an existing accessor) instead of `instance_variable_get` in tests.
    RUBY
  end

  it "does not register an offense when using `instance_variable_defined?`" do
    expect_no_offenses(<<~RUBY)
      described_class.instance_variable_defined?(:@version)
    RUBY
  end

  it "does not register an offense for direct accessor calls" do
    expect_no_offenses(<<~RUBY)
      formula.tap = CoreTap.instance
    RUBY
  end
end
