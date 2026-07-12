# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/release"

RSpec.describe Homebrew::DevCmd::Release do
  it_behaves_like "parseable arguments"

  describe "#run" do
    it "requires an up-to-date origin/main before triggering the release workflow" do
      command = described_class.new(["--force"])

      allow(Homebrew::EnvConfig).to receive(:no_auto_update?).and_return(false)
      allow(GitHub).to receive_messages(
        get_latest_release:     { "tag_name" => "1.2.3" },
        generate_release_notes: { "body" => "Release notes" },
      )
      allow(Utils).to receive(:safe_popen_read).with(
        "git", "-C", HOMEBREW_REPOSITORY, "rev-parse", "origin/main"
      ).and_return("local-sha\n")
      allow(GitHub::API).to receive(:open_rest).with(
        "#{GitHub::API_URL}/repos/Homebrew/brew/releases?per_page=#{GitHub::MAX_PER_PAGE}",
        request_method: :GET,
        scopes:         GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES,
      ).and_return([])
      expect(GitHub::API).to receive(:commit).with("Homebrew", "brew").and_return({ "sha" => "upstream-sha" })
      expect(GitHub).not_to receive(:workflow_dispatch_event)

      expect { command.run }
        .to raise_error(SystemExit)
        .and output(/Run `brew update` before `brew release --force`\./).to_stderr
    end
  end

  describe "release lookup helpers" do
    let(:command) { described_class.new([]) }
    let(:releases) do
      [
        {
          "id"         => 1,
          "name"       => "1.2.3",
          "created_at" => "2025-01-01T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3",
        },
        {
          "id"         => 2,
          "name"       => "1.2.3",
          "created_at" => "2025-01-02T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3-2",
        },
        {
          "id"         => 3,
          "name"       => "1.2.2",
          "created_at" => "2024-12-31T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.2",
        },
        {
          "id"         => 4,
          "name"       => nil,
          "tag_name"   => "1.2.3",
          "created_at" => "2025-01-03T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3-3",
        },
      ]
    end

    before do
      allow(GitHub::API).to receive(:open_rest).and_return(releases)
    end

    it "filters releases by name or tag name" do
      matching = command.send(:matching_releases, "1.2.3")
      expect(matching.map { |release| release["id"] }).to eq([1, 2, 4])
    end

    it "selects the latest matching release by creation time" do
      latest = command.send(:latest_matching_release, "1.2.3")
      expect(latest["id"]).to eq(4)
    end
  end
end
