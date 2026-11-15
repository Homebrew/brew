# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-formula-feeds"

RSpec.describe Homebrew::DevCmd::GenerateFormulaFeeds do
  let(:arguments) { ["--output=#{output_path}"] }
  let(:path) { repository/"Formula/example.rb" }
  let(:output_path) { mktmpdir/"feeds.json" }
  let(:repository) { CoreTap.instance.path }

  before do
    system "git", "-C", repository, "init", "--quiet", exception: true
    path.dirname.mkpath
    path.write <<~RUBY
      class Example < Formula
        url "https://example.test/example-1.0.tar.gz"
        sha256 "#{"a" * 64}"
      end
    RUBY
    system "git", "-C", repository, "add", ".", exception: true
    system "git", "-C", repository, "-c", "user.name=Feed tests", "-c", "user.email=feeds@example.test",
           "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
           "commit", "--quiet", "-m", "Update formula", exception: true
    system "git", "-C", repository, "update-ref", "refs/remotes/origin/main", "HEAD", exception: true
    system "git", "-C", repository, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main",
           exception: true
  end

  it_behaves_like "parseable arguments"

  it "writes entries through the command", :integration_test do
    expect { brew "generate-formula-feeds", *arguments }
      .to output(/Generated 1 new and 0 updated formula entries/).to_stdout
  end

  it "writes stable JSON for origin/HEAD" do
    revision = Utils.safe_popen_read("git", "-C", repository, "rev-parse", "origin/HEAD").strip
    described_class.new(arguments).run
    original = output_path.read
    described_class.new(arguments).run

    expect([JSON.parse(original), output_path.read]).to match([
      { "revision" => revision, "new" => [include("name" => "example", "versions" => ["1.0"])], "updated" => [] },
      original,
    ])
  end

  it "replaces the output without modifying the file held by existing readers" do
    output_path.write("previous data")
    output_path.open do |previous|
      described_class.new(arguments).run

      expect([previous.read, JSON.parse(output_path.read).fetch("new").first.fetch("name")])
        .to eq(["previous data", "example"])
    end
  end

  it "leaves the previous output intact when formula metadata cannot be read" do
    output_path.write("previous data")
    path.write("class Example < Formula\n  invalid_metadata!\nend\n")
    system "git", "-C", repository, "add", ".", exception: true
    system "git", "-C", repository, "-c", "user.name=Feed tests", "-c", "user.email=feeds@example.test",
           "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
           "commit", "--quiet", "-m", "Invalid formula", exception: true
    system "git", "-C", repository, "update-ref", "refs/remotes/origin/main", "HEAD", exception: true

    expect { described_class.new(arguments).run }.to raise_error(/Cannot read formula metadata/)
    expect(output_path.read).to eq("previous data")
  end
end
