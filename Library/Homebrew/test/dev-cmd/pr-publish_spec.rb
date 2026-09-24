# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/pr-publish"

RSpec.describe Homebrew::DevCmd::PrPublish do
  it_behaves_like "parseable arguments"

  describe "#run" do
    it "passes `--warn-on-upload-failure` to the workflow" do
      allow(GitHub).to receive(:pull_request_labels).and_return([])
      expect(GitHub).to receive(:workflow_dispatch_event)
        .with("Homebrew", "homebrew-core", "publish-commit-bottles.yml", "main",
              hash_including(pull_request: "12345", warn_on_upload_failure: true))

      expect { described_class.new(["--warn-on-upload-failure", "12345"]).run }
        .to output(%r{Dispatching homebrew/core pull request #12345}).to_stdout
    end
  end
end
