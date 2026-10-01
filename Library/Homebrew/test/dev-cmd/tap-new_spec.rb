# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/tap-new"
require "yaml"

RSpec.describe Homebrew::DevCmd::TapNew do
  it_behaves_like "parseable arguments"

  it "initializes a new tap with a README file and GitHub Actions CI", :integration_test do
    ENV["HOMEBREW_GIT_NAME"] = "Homebrew Test"
    ENV["HOMEBREW_GIT_EMAIL"] = "test@example.com"

    expect { brew "tap-new", "--verbose", "homebrew/foo" }
      .to be_a_success
      .and output(%r{homebrew/foo}).to_stdout
      .and not_to_output.to_stderr

    expect(HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/README.md").to exist
    expect(Utils.safe_popen_read("git", "-C", HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo",
                                 "log", "-1", "--format=%s"))
      .to eq("Create homebrew/foo tap\n")
    dependabot_yml = (HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/dependabot.yml").read
    tests_yml = (HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/tests.yml").read
    publish_yml = (HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/publish.yml").read
    autobump_yml = (HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo/.github/workflows/autobump.yml").read
    [dependabot_yml, tests_yml, publish_yml].each { YAML.parse(it) }
    expect(tests_yml).not_to include("HOMEBREW_DEVELOPER")
    expect(tests_yml).to include("options: --privileged")
    expect(publish_yml).not_to include("HOMEBREW_DEVELOPER")
    expect(publish_yml).not_to include("pull_request_target")
    expect(publish_yml).not_to include("workflow_run")
    expect(publish_yml).to include("workflow_dispatch:")
    expect(publish_yml).to include("description: Expected pull request head commit SHA (optional)")
    expect(publish_yml).to include("attestations: write")
    expect(publish_yml).to include("id-token: write")
    expect(publish_yml).not_to include("gh pr view")
    expect(publish_yml).to include("id: pull_bottles")
    expect(publish_yml).to include('brew pr-pull --debug --retain-bottle-dir --tap="$GITHUB_REPOSITORY" ' \
                                   '--head-sha="$HEAD_SHA"')
    expect(publish_yml).to include('brew pr-pull --debug --retain-bottle-dir --tap="$GITHUB_REPOSITORY" ' \
                                   '"$PULL_REQUEST"')
    expect(publish_yml).to include("name: Generate build provenance")
    expect(publish_yml).to include('subject-path: "${{ steps.pull_bottles.outputs.bottle_path }}/*.tar.gz"')
    expect(autobump_yml).not_to include("HOMEBREW_DEVELOPER")
    expect(autobump_yml).not_to include("pull_request_target")
    expect(autobump_yml).not_to include("workflow_run")
    expect(autobump_yml).not_to include("TAP_NEW_")
    expect(autobump_yml).not_to include("cron: \"1 1 1 1 1\"")
    expect(autobump_yml).not_to include("# this will be changed later and randomised by brew tap-new")
    expect(autobump_yml).to include("- main")
    expect(autobump_yml).to include('brew bump --no-fork --open-pr --formulae --bump-synced --tap="$TAP_NAME"')
  end
end
