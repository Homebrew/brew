# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Lha do
  let(:path) { TEST_FIXTURE_DIR/"test.lha" }

  include_examples "UnpackStrategy::detect"
end
