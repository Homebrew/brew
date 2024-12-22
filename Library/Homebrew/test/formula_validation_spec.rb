# frozen_string_literal: true

require "formula"

RSpec.describe Formula do
  describe "::new" do
    matcher :fail_with_invalid do |attr|
      match do |actual|
        expect do
          actual.call
        rescue => e
          expect(e.attr).to eq(attr)
          raise e
        end.to raise_error(FormulaValidationError)
      end

      def supports_block_expectations?
        true
      end
    end

    it "can't override the `brew` method" do
      expect do
        formula do
          def brew; end
        end
      end.to raise_error(RuntimeError, /\AThe method `brew` on #{described_class} was declared as final/)
    end

    it "validates the `name`" do
      expect do
        formula "name with spaces" do
          url "foo"
          version "1.0"
        end
      end.to fail_with_invalid :name
    end

    it "validates the `url`" do
      expect do
        formula do
          url ""
          version "1"
        end
      end.to fail_with_invalid :url
    end

    it "validates the `version`" do
      expect do
        formula do
          url "foo"
          version "version with spaces"
        end
      end.to fail_with_invalid :version

      expect do
        formula do
          url "foo"
          version ""
        end
      end.to fail_with_invalid :version

      expect do
        formula do
          url "foo"
          version nil
        end
      end.to fail_with_invalid :version
    end

    specify "head-only is valid" do
      f = formula do
        head "foo"
      end

      expect(f).to be_head
    end

    it "fails when Formula is empty" do
      expect do
        formula do
          # do nothing
        end
      end.to raise_error(FormulaSpecificationError)
    end
  end
end
