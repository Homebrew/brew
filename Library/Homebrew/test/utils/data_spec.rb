# typed: strict
# frozen_string_literal: true

require "utils/data"

RSpec.describe Utils::Data do
  describe ".assert_valid_keys" do
    it "accepts valid keys" do
      expect { described_class.assert_valid_keys({ name: "Homebrew" }, :name) }.not_to raise_error
    end

    it "rejects invalid keys" do
      expect { described_class.assert_valid_keys({ name: "Homebrew" }, :version) }
        .to raise_error(ArgumentError, "Unknown key: :name. Valid keys are: :version")
    end
  end
end
