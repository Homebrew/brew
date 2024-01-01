# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Gzip do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.gz" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"]
end
