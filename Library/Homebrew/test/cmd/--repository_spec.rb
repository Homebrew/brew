# typed: strict
# frozen_string_literal: true

require "open3"

RSpec.describe "brew --repository", type: :system do
  it "prints Homebrew and Tap repositories" do
    stdout, stderr, status = Open3.capture3(
      {
        "HOMEBREW_LIBRARY"    => ENV.fetch("HOMEBREW_LIBRARY"),
        "HOMEBREW_REPOSITORY" => ENV.fetch("HOMEBREW_REPOSITORY"),
      },
      "/bin/bash", "-c", <<~SH,
        source "$1"
        homebrew---repository
        homebrew---repository foo/bar foo/homebrew-bar
      SH
      "bash", (HOMEBREW_LIBRARY_PATH/"cmd/--repository.sh").to_s
    )

    expect(status).to be_success
    expect(stdout).to eq(<<~EOS)
      #{ENV.fetch("HOMEBREW_REPOSITORY")}
      #{ENV.fetch("HOMEBREW_LIBRARY")}/Taps/foo/homebrew-bar
      #{ENV.fetch("HOMEBREW_LIBRARY")}/Taps/foo/homebrew-bar
    EOS
    expect(stderr).to be_empty
  end
end
