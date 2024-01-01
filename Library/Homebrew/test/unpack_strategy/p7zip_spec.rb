# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::P7Zip do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.7z" }

  include_examples "UnpackStrategy::detect"
end
