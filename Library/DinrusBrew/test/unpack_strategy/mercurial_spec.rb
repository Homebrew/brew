# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Mercurial do
  let(:repo) do
    mktmpdir.tap do |repo|
      (repo/".hg").mkpath
    end
  end
  let(:path) { repo }

  include_examples "UnpackStrategy::detect"
end
