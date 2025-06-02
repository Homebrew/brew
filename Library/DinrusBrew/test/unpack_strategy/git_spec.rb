# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Git do
  let(:repo) do
    mktmpdir.tap do |repo|
      system "git", "-C", repo, "init"

      FileUtils.touch repo/"test"
      system "git", "-C", repo, "add", "test"
      system "git", "-C", repo, "commit", "-m", "Add `test` file."
    end
  end
  let(:path) { repo }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: [".git", "test"]
end
