# typed: false
# frozen_string_literal: true

require "ignorable"

RSpec.describe Ignorable do
  def raise_runtime_error
    raise "raised in block"
  end

  describe "::hook_raise" do
    it "resumes execution after the raise site when the handler returns :ignore" do
      steps = []
      result = described_class.hook_raise(on_ignorable: ->(_e) { :ignore }) do
        steps << :before
        raise_runtime_error
        steps << :after
        steps
      end
      expect(result).to eq([:before, :after])
    end

    it "extends exceptions passed to the handler with ExceptionMixin" do
      exception = nil
      described_class.hook_raise(on_ignorable: lambda { |e|
        exception = e
        :ignore
      }) { raise_runtime_error }
      expect(exception).to be_a(described_class::ExceptionMixin)
    end

    it "raises at the raise site when the handler returns :raise" do
      result = described_class.hook_raise(on_ignorable: ->(_e) { :raise }) do
        raise_runtime_error
      rescue RuntimeError
        :rescued_in_block
      end
      expect(result).to eq(:rescued_in_block)
    end

    it "propagates unrescued exceptions when the handler returns :raise" do
      expect do
        described_class.hook_raise(on_ignorable: ->(_e) { :raise }) { raise_runtime_error }
      end.to raise_error(RuntimeError, "raised in block")
    end

    it "preserves the exception's backtrace when the handler returns :raise" do
      yielded_backtrace = nil
      exception = nil
      begin
        described_class.hook_raise(on_ignorable: lambda { |e|
          yielded_backtrace = e.backtrace.dup
          :raise
        }) { raise_runtime_error }
      rescue RuntimeError => e
        exception = e
      end
      expect(exception.backtrace).to eq(yielded_backtrace)
    end

    it "runs the block's ensure blocks when the handler raises" do
      ensured = false
      expect do
        described_class.hook_raise(on_ignorable: ->(e) { raise e }) do
          raise_runtime_error
        ensure
          ensured = true
        end
      end.to raise_error(RuntimeError, "raised in block")
      expect(ensured).to be(true)
    end

    it "does not consult the handler for exceptions not raised from Ruby code" do
      expect do
        described_class.hook_raise(on_ignorable: ->(_e) { :ignore }) { Integer("nope") }
      end.to raise_error(ArgumentError)
    end

    it "does not consult the handler for ScriptError" do
      expect do
        described_class.hook_raise(on_ignorable: ->(_e) { :ignore }) { raise NotImplementedError }
      end.to raise_error(NotImplementedError)
    end

    it "restores the original raise afterwards" do
      described_class.hook_raise(on_ignorable: ->(_e) { :raise }) { :noop }
      expect(Object.instance_method(:raise).owner).to eq(Kernel)
    end

    it "restores the original raise when an exception propagates" do
      begin
        described_class.hook_raise(on_ignorable: ->(_e) { :raise }) { raise_runtime_error }
      rescue RuntimeError
        nil
      end
      expect(Object.instance_method(:fail).owner).to eq(Kernel)
    end
  end
end
