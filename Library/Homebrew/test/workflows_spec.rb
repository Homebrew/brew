# typed: strict
# frozen_string_literal: true

require "open3"
require "yaml"

RSpec.describe "Workflows" do
  test_each([
    ["vendor-gems", "push-target", [0, 1, 1, 1, 1]],
    ["tap-new-publish", "pull_bottles", [0, 0, 0, 0, 0]],
  ]) do |workflow, step_id, expected_statuses|
    it "accepts the expected pull request origins for #{workflow}" do
      step = YAML.load_file(HOMEBREW_LIBRARY_PATH.parent.parent/".github/workflows/#{workflow}.yml")
                 .fetch("jobs").values.fetch(0).fetch("steps").find { |s| s["id"] == step_id }
      raise "Missing workflow step #{step_id}" unless step

      results = [
        ["Homebrew/brew", 0],
        ["contributor/brew", 0],
        ["Homebrew/other", 0],
        ["null", 0],
        ["Homebrew/brew", 1],
      ].map do |head_repository, api_status|
        ENV["GITHUB_EVENT_NAME"] = "workflow_dispatch"
        ENV["GITHUB_REPOSITORY"] = "Homebrew/brew"
        ENV["PR"] = ENV["PULL_REQUEST"] = "123"
        ENV["HEAD_SHA"] = ""
        ENV["HEAD_REPOSITORY"] = head_repository
        ENV["API_STATUS"] = api_status.to_s
        _, _, status = Open3.capture3("/bin/bash", "-euo", "pipefail", "-c", <<~BASH)
          gh() {
            if [[ "$1" == "api" && "$2" == "repos/Homebrew/brew/pulls/123" ]]
            then
              printf '%s\\n' "$HEAD_REPOSITORY"
              return "$API_STATUS"
            fi
            exit 0
          }
          brew() { exit 0; }
          #{step.fetch("run")}
        BASH

        status.exitstatus
      end

      expect(results).to eq(expected_statuses)
    end
  end
end
