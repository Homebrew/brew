# typed: strict
# frozen_string_literal: true

require "rubocops/no_send_in_tests"

RSpec.describe RuboCop::Cop::Homebrew::NoSendInTests, :config do
  it "registers an offense when using `send` with a static method name" do
    expect_offense(<<~RUBY)
      formula.send(:active_spec)
              ^^^^ Make the method public and call it directly instead of using `send` in tests.
    RUBY
  end

  it "registers an offense when using `send` without a receiver" do
    expect_offense(<<~RUBY)
      send(:generate_runners!)
      ^^^^ Make the method public and call it directly instead of using `send` in tests.
    RUBY
  end

  it "registers an offense when using `__send__`" do
    expect_offense(<<~RUBY)
      formula.__send__(:active_spec)
              ^^^^^^^^ Make the method public and call it directly instead of using `__send__` in tests.
    RUBY
  end

  it "registers an offense when using `send` with a safe navigation operator" do
    expect_offense(<<~RUBY)
      formula&.send(:active_spec)
               ^^^^ Make the method public and call it directly instead of using `send` in tests.
    RUBY
  end

  it "registers an offense when using `send` with a dynamic method name" do
    expect_offense(<<~'RUBY')
      formula.send(:"#{action}_network_access!")
              ^^^^ Use `public_send` instead of `send` in tests; `send` bypasses method visibility.
    RUBY
  end

  it "registers an offense when using `public_send` with a static method name" do
    expect_offense(<<~RUBY)
      formula.public_send(:active_spec)
              ^^^^^^^^^^^ Call the method directly instead of using `public_send` with a static method name.
    RUBY
  end

  it "registers an offense when using `public_send` with a static string method name" do
    expect_offense(<<~RUBY)
      formula.public_send("active_spec")
              ^^^^^^^^^^^ Call the method directly instead of using `public_send` with a static method name.
    RUBY
  end

  it "registers an offense when using `public_send` with a static setter method name" do
    expect_offense(<<~RUBY)
      formula.public_send(:name=, "foo")
              ^^^^^^^^^^^ Call the method directly instead of using `public_send` with a static method name.
    RUBY
  end

  it "does not register an offense when using `public_send` with a dynamic method name" do
    expect_no_offenses(<<~'RUBY')
      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    RUBY
  end

  it "does not register an offense when using `public_send` with a variable method name" do
    expect_no_offenses(<<~RUBY)
      described_class.public_send(method_name, TEST_TMPDIR, safe: false)
    RUBY
  end

  it "does not register an offense when using `public_send` with a method name that has no call syntax" do
    expect_no_offenses(<<~RUBY)
      subject.public_send(:"gcc-9")
    RUBY
  end

  it "does not register an offense for a direct method call" do
    expect_no_offenses(<<~RUBY)
      formula.active_spec
    RUBY
  end
end
