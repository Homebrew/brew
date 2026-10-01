# typed: true
# frozen_string_literal: true

require "rubocops/public_api_cookbook"

RSpec.describe RuboCop::Cop::Homebrew::PublicApiCookbook do
  subject(:cop) { described_class.new }

  let(:formula_path) { "formula.rb" }
  let(:cask_dsl_path) { "cask/dsl.rb" }
  let(:helper_path) { "rubocops/shared/api_annotation_helper.rb" }

  let(:service_path) { "service.rb" }

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

  context "when a formula cookbook method is missing from the helper list" do
    before do
      (mktmpdir/"docs").tap do |docs|
        docs.mkpath
        (docs/"Formula-Cookbook.md").write <<~MARKDOWN
          [`new_api`](/rubydoc/Formula.html#new_api-instance_method)
        MARKDOWN

        stub_const("HOMEBREW_LIBRARY_PATH", docs.parent/"Library/Homebrew")
      end

      stub_const("RuboCop::Cop::ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS", {})
      stub_const("RuboCop::Cop::ApiAnnotationHelper::SERVICE_COOKBOOK_METHODS", Set.new)
    end

    it "reports an offense" do
      expect_offense(<<~RUBY, helper_path)
        module ApiAnnotationHelper
          FORMULA_COOKBOOK_METHODS = {}.freeze
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: Formula Cookbook references methods missing from `FORMULA_COOKBOOK_METHODS`: `new_api`.
        end
      RUBY
    end
  end

  context "when a public cask method is missing from the helper list" do
    before do
      stub_const("RuboCop::Cop::ApiAnnotationHelper::CASK_COOKBOOK_METHODS", {})
    end

    it "reports an offense" do
      expect_offense(<<~RUBY, cask_dsl_path)
        module Cask
          module DSL
            # The new stanza.
            #
            # @api public
            ^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: Method `new_stanza` is annotated with `@api public` in `cask/dsl.rb` but is missing from `CASK_COOKBOOK_METHODS`.
            def new_stanza; end
          end
        end
      RUBY
    end
  end

  context "when a documented service block method lacks `@api public`" do
    it "reports an offense" do
      expect_offense(<<~RUBY, service_path)
        class Service
          def require_root(value = nil); end
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: Method `require_root` is referenced in the Formula Cookbook but is not annotated with `@api public`.
        end
      RUBY
    end
  end

  context "when a documented service block method has `@api public`" do
    it "does not report an offense" do
      expect_no_offenses(<<~RUBY, service_path)
        class Service
          # Whether the service requires root access.
          #
          # @api public
          def require_root(value = nil); end
        end
      RUBY
    end
  end

  context "when a service method has `@api public` but is not documented" do
    it "reports an offense" do
      expect_offense(<<~RUBY, service_path)
        class Service
          # An undocumented method.
          #
          # @api public
          def undocumented; end
          ^^^^^^^^^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: Method `undocumented` is annotated with `@api public` in `service.rb` but is missing from the Formula Cookbook's "Service block methods" table.
        end
      RUBY
    end
  end

  context "when `SERVICE_COOKBOOK_METHODS` does not match the cookbook table" do
    before do
      (mktmpdir/"docs").tap do |docs|
        docs.mkpath
        (docs/"Formula-Cookbook.md").write <<~MARKDOWN
          #### Service block methods

          | method  | description |
          | ------- | ----------- |
          | `run`   | command     |

          #### Next section
        MARKDOWN

        stub_const("HOMEBREW_LIBRARY_PATH", docs.parent/"Library/Homebrew")
      end

      stub_const("RuboCop::Cop::ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS", {})
      stub_const("RuboCop::Cop::ApiAnnotationHelper::SERVICE_COOKBOOK_METHODS", Set["run", "extra"])
    end

    it "reports an offense" do
      expect_offense(<<~RUBY, helper_path)
        module ApiAnnotationHelper
          SERVICE_COOKBOOK_METHODS = [].to_set.freeze
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew/PublicApiCookbook: `SERVICE_COOKBOOK_METHODS` is out of sync with the Formula Cookbook's "Service block methods" table: not in the cookbook table: `extra`.
        end
      RUBY
    end
  end
end
