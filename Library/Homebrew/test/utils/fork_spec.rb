# frozen_string_literal: true

require "utils/fork"

RSpec.describe Utils do
  describe "#safe_fork" do
    it "raises a RuntimeError on an error that isn't ErrorDuringExecution" do
      expect do
        described_class.safe_fork do
          raise "this is an exception in the child"
        end
      end.to raise_error(RuntimeError)
    end

    it "raises an ErrorDuringExecution on one in the child" do
      expect do
        described_class.safe_fork do
          safe_system "/usr/bin/false"
        end
      end.to raise_error(ErrorDuringExecution)
    end
  end
end
