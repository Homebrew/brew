# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Dmg, :needs_macos do
  describe "#mount" do
    let(:path) { TEST_FIXTURE_DIR/"cask/container.dmg" }

    include_examples "UnpackStrategy::detect"
    include_examples "#extract", children: ["container"]
  end
end
