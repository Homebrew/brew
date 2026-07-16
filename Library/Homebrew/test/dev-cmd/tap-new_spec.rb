# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/tap-new"

RSpec.describe Homebrew::DevCmd::TapNew do
  it_behaves_like "parseable arguments"

  it "initializes a new tap with a README file and GitHub Actions CI", :integration_test do
    # To ensure that Utils::Git.setup_gpg! doesn't raise an error
    setup_test_formula "gnupg"

    expect { brew "tap-new", "--no-git", "--verbose", "homebrew/foo" }
      .to be_a_success
      .and output(%r{homebrew/foo}).to_stdout
      .and not_to_output.to_stderr

    expect(HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/README.md").to exist
    expect(HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/tests.yml").to exist
    expect((HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/tests.yml").read)
      .not_to include("HOMEBREW_DEVELOPER")
    expect((HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/tests.yml").read)
      .to include("options: ${{ matrix.container != '' && '--privileged' }}")
    publish_yml = (HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/publish.yml").read
    expect(publish_yml).not_to include("HOMEBREW_DEVELOPER")
    expect(publish_yml).not_to include("pull_request_target")
    expect(publish_yml).not_to include("workflow_run")
    expect(publish_yml).to include("workflow_dispatch:")
    expect(publish_yml).to include("description: Expected pull request head commit SHA (optional)")
    expect(publish_yml).not_to include("gh pr view")
    expect(publish_yml).to include('brew pr-pull --debug --tap="$GITHUB_REPOSITORY" --head-sha="$HEAD_SHA"')
    expect(publish_yml).to include('brew pr-pull --debug --tap="$GITHUB_REPOSITORY" "$PULL_REQUEST"')
  end
end
