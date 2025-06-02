# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Bzip2 do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.bz2" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"]
end
