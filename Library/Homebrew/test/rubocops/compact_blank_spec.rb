# frozen_string_literal: true

require "rubocops/compact_blank"

RSpec.describe RuboCop::Cop::Homebrew::CompactBlank, :config do
  it "registers and corrects an offense when using `reject { |e| e.blank? }`" do
    expect_offense(<<~RUBY)
      collection.reject { |e| e.blank? }
                 ^^^^^^^^^^^^^^^^^^^^^^^ Use `compact_blank` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank
    RUBY
  end

  it "registers and corrects an offense when using `reject(&:blank?)`" do
    expect_offense(<<~RUBY)
      collection.reject(&:blank?)
                 ^^^^^^^^^^^^^^^^ Use `compact_blank` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank
    RUBY
  end

  it "registers and corrects an offense when using `delete_if { |e| e.blank? }`" do
    expect_offense(<<~RUBY)
      collection.delete_if { |e| e.blank? }
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `compact_blank!` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank!
    RUBY
  end

  it "registers and corrects an offense when using `delete_if(&:blank?)`" do
    expect_offense(<<~RUBY)
      collection.delete_if(&:blank?)
                 ^^^^^^^^^^^^^^^^^^^ Use `compact_blank!` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank!
    RUBY
  end

  it "registers and corrects an offense when using `reject! { |e| e.blank? }`" do
    expect_offense(<<~RUBY)
      collection.reject! { |e| e.blank? }
                 ^^^^^^^^^^^^^^^^^^^^^^^^ Use `compact_blank!` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank!
    RUBY
  end

  it "registers and corrects an offense when using `reject!(&:blank?)`" do
    expect_offense(<<~RUBY)
      collection.reject!(&:blank?)
                 ^^^^^^^^^^^^^^^^^ Use `compact_blank!` instead.
    RUBY

    expect_correction(<<~RUBY)
      collection.compact_blank!
    RUBY
  end

  it "registers and corrects an offense when using `reject(&:blank?)` in block" do
    expect_offense(<<~RUBY)
      hash.transform_values { |value| value.reject(&:blank?) }
                                            ^^^^^^^^^^^^^^^^ Use `compact_blank` instead.
    RUBY

    expect_correction(<<~RUBY)
      hash.transform_values { |value| value.compact_blank }
    RUBY
  end

  it "does not register an offense when using `compact_blank`" do
    expect_no_offenses(<<~RUBY)
      collection.compact_blank
    RUBY
  end

  it "does not register an offense when using `compact_blank!`" do
    expect_no_offenses(<<~RUBY)
      collection.compact_blank!
    RUBY
  end

  it "does not register an offense when using `reject { |k, v| k.blank? }`" do
    expect_no_offenses(<<~RUBY)
      collection.reject { |k, v| k.blank? }
    RUBY
  end

  it "does not register an offense when using the receiver of `blank?` is not a block variable" do
    expect_no_offenses(<<~RUBY)
      def foo(arg)
        collection.reject { |_| arg.blank? }
      end
    RUBY
  end

  it "does not register an offense when using `reject { |e| e.empty? }`" do
    expect_no_offenses(<<~RUBY)
      collection.reject { |e| e.empty? }
    RUBY
  end
end
