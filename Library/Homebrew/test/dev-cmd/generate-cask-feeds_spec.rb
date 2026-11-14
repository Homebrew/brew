# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-feeds"

RSpec.describe Homebrew::DevCmd::GenerateCaskFeeds do
  sig { returns(Pathname) }
  let(:repository) { CoreCaskTap.instance.path }

  before do
    (repository/"Casks").mkpath
    (repository/"Casks/example.rb").write <<~RUBY
      cask "example" do
        version "1.0"
        sha256 "#{"a" * 64}"
        url "https://example.test/example.dmg"
        homepage "https://example.test"
      end
    RUBY
    (repository/"Formula").mkpath
    (repository/"Formula/ignored.rb").write("invalid_metadata!\n")
    system "git", "-C", repository.to_s, "init", "--quiet", exception: true
    system "git", "-C", repository.to_s, "add", ".", exception: true
    system "git", "-C", repository.to_s, "-c", "user.name=Feed tests", "-c", "user.email=feeds@example.test",
           "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
           "commit", "--quiet", "-m", "Add cask", exception: true
    system "git", "-C", repository.to_s, "update-ref", "refs/remotes/origin/main", "HEAD", exception: true
    system "git", "-C", repository.to_s, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
           exception: true
  end

  it_behaves_like "parseable arguments"

  it "writes cask entries through the command", :integration_test do
    output_path = mktmpdir/"feeds.json"

    expect { brew "generate-cask-feeds", "--output=#{output_path}" }
      .to output(/Generated 1 new and 0 updated cask entries/).to_stdout
    expect(JSON.parse(output_path.read)).to include(
      "new" => [include("name" => "example", "versions" => ["1.0"])], "updated" => [],
    )
  end

  it "defaults to the cask tap and output path" do
    mktmpdir.cd do
      described_class.new([]).run

      expect(JSON.parse(Pathname("_data/cask_feeds.json").read)).to include(
        "new" => [include("name" => "example", "versions" => ["1.0"])], "updated" => [],
      )
    end
  end
end
