# frozen_string_literal: true

require "rubocops/present"

RSpec.describe RuboCop::Cop::Homebrew::Present, :config do
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

  it "accepts checking existence && not empty? on different objects" do
    expect_no_offenses("foo && !bar.empty?")
  end

  it_behaves_like "offense", "foo && !foo.empty?",
                  "foo.present?",
                  "Use `foo.present?` instead of `foo && !foo.empty?`."
  it_behaves_like "offense", "!foo.nil? && !foo.empty?",
                  "foo.present?",
                  "Use `foo.present?` instead of `!foo.nil? && !foo.empty?`."
  it_behaves_like "offense", "!nil? && !empty?", "present?",
                  "Use `present?` instead of `!nil? && !empty?`."
  it_behaves_like "offense", "foo != nil && !foo.empty?",
                  "foo.present?",
                  "Use `foo.present?` instead of `foo != nil && !foo.empty?`."
  it_behaves_like "offense", "!!foo && !foo.empty?",
                  "foo.present?",
                  "Use `foo.present?` instead of `!!foo && !foo.empty?`."

  context "when checking all variable types" do
    it_behaves_like "offense", "!foo.nil? && !foo.empty?",
                    "foo.present?",
                    "Use `foo.present?` instead of " \
                    "`!foo.nil? && !foo.empty?`."
    it_behaves_like "offense", "!foo.bar.nil? && !foo.bar.empty?",
                    "foo.bar.present?",
                    "Use `foo.bar.present?` instead of " \
                    "`!foo.bar.nil? && !foo.bar.empty?`."
    it_behaves_like "offense", "!FOO.nil? && !FOO.empty?",
                    "FOO.present?",
                    "Use `FOO.present?` instead of " \
                    "`!FOO.nil? && !FOO.empty?`."
    it_behaves_like "offense", "!Foo.nil? && !Foo.empty?",
                    "Foo.present?",
                    "Use `Foo.present?` instead of " \
                    "`!Foo.nil? && !Foo.empty?`."
    it_behaves_like "offense", "!@foo.nil? && !@foo.empty?",
                    "@foo.present?",
                    "Use `@foo.present?` instead of " \
                    "`!@foo.nil? && !@foo.empty?`."
    it_behaves_like "offense", "!$foo.nil? && !$foo.empty?",
                    "$foo.present?",
                    "Use `$foo.present?` instead of " \
                    "`!$foo.nil? && !$foo.empty?`."
    it_behaves_like "offense", "!@@foo.nil? && !@@foo.empty?",
                    "@@foo.present?",
                    "Use `@@foo.present?` instead of " \
                    "`!@@foo.nil? && !@@foo.empty?`."
    it_behaves_like "offense", "!foo[bar].nil? && !foo[bar].empty?",
                    "foo[bar].present?",
                    "Use `foo[bar].present?` instead of " \
                    "`!foo[bar].nil? && !foo[bar].empty?`."
    it_behaves_like "offense", "!Foo::Bar.nil? && !Foo::Bar.empty?",
                    "Foo::Bar.present?",
                    "Use `Foo::Bar.present?` instead of " \
                    "`!Foo::Bar.nil? && !Foo::Bar.empty?`."
    it_behaves_like "offense", "!foo(bar).nil? && !foo(bar).empty?",
                    "foo(bar).present?",
                    "Use `foo(bar).present?` instead of " \
                    "`!foo(bar).nil? && !foo(bar).empty?`."
  end
end
