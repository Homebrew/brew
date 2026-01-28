# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Zip do
  let(:path) { TEST_FIXTURE_DIR/"cask/MyFancyApp.zip" }

  include_examples "UnpackStrategy::detect"

  context "when unzip is available", :needs_unzip do
    include_examples "#extract", children: ["MyFancyApp"]
  end

  context "when ZIP archive is corrupted" do
    let(:path) do
      (mktmpdir/"test.zip").tap do |path|
        FileUtils.touch path
      end
    end

    include_examples "UnpackStrategy::detect"
  end
end
