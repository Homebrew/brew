# typed: false
# frozen_string_literal: true

require "rubocops/public_api_cookbook"

RSpec.describe RuboCop::Cop::Homebrew::PublicApiCookbook do
  subject(:cop) { described_class.new }

  let(:formula_path) { "formula.rb" }
  let(:cask_dsl_path) { "cask/dsl.rb" }

  context "when a cookbook-referenced method lacks `@api public`" do
    it "reports an offense for a formula method" do
      expect_offense(<<~RUBY, formula_path)
        class Formula
          def libexec
          ^^^^^^^^^^^ Homebrew/PublicApiCookbook: Method `libexec` is referenced in the Formula Cookbook but is not annotated with `@api public`.
            prefix/"libexec"
          end
        end
      RUBY
    end
  end

  context "when a cookbook-referenced method has `@api public`" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY, formula_path)
        class Formula
          # The libexec directory.
          #
          # @api public
          def libexec
            prefix/"libexec"
          end
        end
      RUBY
    end
  end

  context "when the file is not a cookbook source file" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY, "some_other_file.rb")
        class Something
          def libexec; end
        end
      RUBY
    end
  end

  context "when a non-cookbook method lacks `@api public`" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY, formula_path)
        class Formula
          def some_internal_method; end
        end
      RUBY
    end
  end

  context "when checking cask DSL methods" do
    it "reports an offense for a cask cookbook method without @api public" do
      expect_offense(<<~RUBY, cask_dsl_path)
        module Cask
          module DSL
            def desc; end
            ^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: Method `desc` is referenced in the Cask Cookbook but is not annotated with `@api public`.
          end
        end
      RUBY
    end

    it "does not report an offense for an annotated cask method" do
      expect_no_offenses(<<~RUBY, cask_dsl_path)
        module Cask
          module DSL
            # The description of this cask.
            #
            # @api public
            def desc; end
          end
        end
      RUBY
    end
  end
end
