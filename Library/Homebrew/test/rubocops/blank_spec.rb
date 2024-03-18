# frozen_string_literal: true

require "rubocops/blank"

RSpec.describe RuboCop::Cop::Homebrew::Blank, :config do
  shared_examples "offense" do |source, correction, message|
    it "registers an offense and corrects" do
      expect_offense(<<~RUBY, source:, message:)
        #{source}
        ^{source} #{message}
      RUBY

      expect_correction(<<~RUBY)
        #{correction}
      RUBY
    end
  end

  it "accepts checking nil?" do
    expect_no_offenses("foo.nil?")
  end

  it "accepts checking empty?" do
    expect_no_offenses("foo.empty?")
  end

  it "accepts checking nil? || empty? on different objects" do
    expect_no_offenses("foo.nil? || bar.empty?")
  end

  # Bug: https://github.com/rubocop/rubocop/issues/4171
  it "does not break when RHS of `or` is a naked falsiness check" do
    expect_no_offenses("foo.empty? || bar")
  end

  it "does not break when LHS of `or` is a naked falsiness check" do
    expect_no_offenses("bar || foo.empty?")
  end

  # Bug: https://github.com/rubocop/rubocop/issues/4814
  it "does not break when LHS of `or` is a send node with an argument" do
    expect_no_offenses("x(1) || something")
  end

  context "when nil or empty" do
    it_behaves_like "offense", "foo.nil? || foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of `foo.nil? || foo.empty?`."
    it_behaves_like "offense", "nil? || empty?", "blank?", "Use `blank?` instead of `nil? || empty?`."
    it_behaves_like "offense", "foo == nil || foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of `foo == nil || foo.empty?`."
    it_behaves_like "offense", "nil == foo || foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of `nil == foo || foo.empty?`."
    it_behaves_like "offense", "!foo || foo.empty?", "foo.blank?",
                    "Use `foo.blank?` instead of `!foo || foo.empty?`."

    it_behaves_like "offense", "foo.nil? || !!foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of `foo.nil? || !!foo.empty?`."
    it_behaves_like "offense", "foo == nil || !!foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of " \
                    "`foo == nil || !!foo.empty?`."
    it_behaves_like "offense", "nil == foo || !!foo.empty?",
                    "foo.blank?",
                    "Use `foo.blank?` instead of " \
                    "`nil == foo || !!foo.empty?`."
  end

  context "when checking all variable types" do
    it_behaves_like "offense", "foo.bar.nil? || foo.bar.empty?",
                    "foo.bar.blank?",
                    "Use `foo.bar.blank?` instead of " \
                    "`foo.bar.nil? || foo.bar.empty?`."
    it_behaves_like "offense", "FOO.nil? || FOO.empty?",
                    "FOO.blank?",
                    "Use `FOO.blank?` instead of `FOO.nil? || FOO.empty?`."
    it_behaves_like "offense", "Foo.nil? || Foo.empty?",
                    "Foo.blank?",
                    "Use `Foo.blank?` instead of `Foo.nil? || Foo.empty?`."
    it_behaves_like "offense", "Foo::Bar.nil? || Foo::Bar.empty?",
                    "Foo::Bar.blank?",
                    "Use `Foo::Bar.blank?` instead of " \
                    "`Foo::Bar.nil? || Foo::Bar.empty?`."
    it_behaves_like "offense", "@foo.nil? || @foo.empty?",
                    "@foo.blank?",
                    "Use `@foo.blank?` instead of `@foo.nil? || @foo.empty?`."
    it_behaves_like "offense", "$foo.nil? || $foo.empty?",
                    "$foo.blank?",
                    "Use `$foo.blank?` instead of `$foo.nil? || $foo.empty?`."
    it_behaves_like "offense", "@@foo.nil? || @@foo.empty?",
                    "@@foo.blank?",
                    "Use `@@foo.blank?` instead of " \
                    "`@@foo.nil? || @@foo.empty?`."
    it_behaves_like "offense", "foo[bar].nil? || foo[bar].empty?",
                    "foo[bar].blank?",
                    "Use `foo[bar].blank?` instead of " \
                    "`foo[bar].nil? || foo[bar].empty?`."
    it_behaves_like "offense", "foo(bar).nil? || foo(bar).empty?",
                    "foo(bar).blank?",
                    "Use `foo(bar).blank?` instead of " \
                    "`foo(bar).nil? || foo(bar).empty?`."
  end
end
