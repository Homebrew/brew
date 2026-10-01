# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Rar do
  subject(:path) { TEST_FIXTURE_DIR/"cask/container.rar" }

  include_examples "UnpackStrategy::detect", deprecated: true
end
