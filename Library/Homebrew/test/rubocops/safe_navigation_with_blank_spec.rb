# frozen_string_literal: true

require "rubocops/safe_navigation_with_blank"

RSpec.describe RuboCop::Cop::Homebrew::SafeNavigationWithBlank, :config do
  context "when in a conditional" do
    it "registers an offense on a single conditional" do
      expect_offense(<<~RUBY)
        do_something unless foo&.blank?
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid calling `blank?` with the safe navigation operator in conditionals.
      RUBY

      expect_correction(<<~RUBY)
        do_something unless foo.blank?
      RUBY
    end

    it "registers an offense on chained conditionals" do
      expect_offense(<<~RUBY)
        do_something unless foo&.bar&.blank?
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid calling `blank?` with the safe navigation operator in conditionals.
      RUBY

      expect_correction(<<~RUBY)
        do_something unless foo&.bar.blank?
      RUBY
    end

    it "does not register an offense on `.blank?`" do
      expect_no_offenses(<<~RUBY)
        return if foo.blank?
      RUBY
    end
  end

  context "when outside a conditional" do
    it "registers no offense" do
      expect_no_offenses(<<~RUBY)
        bar = foo&.blank?
      RUBY
    end
  end
end
