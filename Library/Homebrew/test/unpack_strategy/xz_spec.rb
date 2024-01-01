# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Xz do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.xz" }

  include_examples "UnpackStrategy::detect"
end
