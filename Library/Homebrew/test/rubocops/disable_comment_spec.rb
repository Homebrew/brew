# frozen_string_literal: true

require "rubocops/disable_comment"

RSpec.describe RuboCop::Cop::DisableComment, :config do
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

  it "registers an offense" do
    expect_offense(<<~RUBY)
      def something; end
      # rubocop:disable Naming/AccessorMethodName
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Add a clarifying comment to the RuboCop disable comment
      def get_decrypted_io; end
    RUBY
  end

  it "registers an offense if the comment is empty" do
    expect_offense(<<~RUBY)
      def something; end
      #
      # rubocop:disable Naming/AccessorMethodName
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Add a clarifying comment to the RuboCop disable comment
      def get_decrypted_io; end
    RUBY
  end

  it "doesn't register an offense" do
    expect_no_offenses(<<~RUBY)
      def something; end
      # This is a upstream name that we cannot change.
      # rubocop:disable Naming/AccessorMethodName
      def get_decrypted_io; end
    RUBY
  end
end
