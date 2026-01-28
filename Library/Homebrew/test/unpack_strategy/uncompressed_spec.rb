# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Uncompressed do
  let(:path) do
    (mktmpdir/"test").tap do |path|
      FileUtils.touch path
    end
  end

  include_examples "UnpackStrategy::detect"
end
