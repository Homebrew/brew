# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Mercurial do
  subject(:path) { repo }

  let(:repo) do
    mktmpdir.tap do |repo|
      (repo/".hg").mkpath
    end
  end

  include_examples "UnpackStrategy::detect"
end
