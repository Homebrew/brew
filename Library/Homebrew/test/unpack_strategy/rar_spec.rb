# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Rar do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.rar" }

  include_examples "UnpackStrategy::detect"
end
