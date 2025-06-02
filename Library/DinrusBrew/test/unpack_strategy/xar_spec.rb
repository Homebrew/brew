# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Xar, :needs_macos do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.xar" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"]
end
