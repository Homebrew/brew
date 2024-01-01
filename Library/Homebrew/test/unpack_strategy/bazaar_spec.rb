# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Bazaar do
  let(:repo) do
    mktmpdir.tap do |repo|
      FileUtils.touch repo/"test"
      (repo/".bzr").mkpath
    end
  end
  let(:path) { repo }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["test"]
end
