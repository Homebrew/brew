# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Bazaar do
  subject(:path) { repo }

  let(:repo) do
    mktmpdir.tap do |repo|
      FileUtils.touch repo/"test"
      (repo/".bzr").mkpath
    end
  end

  include_examples "UnpackStrategy::detect", deprecated: true
  include_examples "#extract", children: ["test"]
end
