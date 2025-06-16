# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Git do
  subject(:git) { described_class }

  let(:git_url) { "https://github.com/Homebrew/brew.git" }
  let(:non_git_url) { "https://brew.sh/test" }

  let(:tags) do
    {
      normal:  ["brew/1.2", "brew/1.2.1", "brew/1.2.2", "brew/1.2.3", "brew/1.2.4", "1.2.5"],
      hyphens: ["brew/1-2", "brew/1-2-1", "brew/1-2-2", "brew/1-2-3", "brew/1-2-4", "1-2-5"],
    }
  end

  let(:regexes) do
    {
      standard: /^v?(\d+(?:\.\d+)+)$/i,
      hyphens:  /^v?(\d+(?:[.-]\d+)+)$/i,
      brew:     %r{^brew/v?(\d+(?:\.\d+)+)$}i,
    }
  end

  let(:versions) do
    {
      default:        ["1.2", "1.2.1", "1.2.2", "1.2.3", "1.2.4", "1.2.5"],
      standard_regex: ["1.2.5"],
      brew_regex:     ["1.2", "1.2.1", "1.2.2", "1.2.3", "1.2.4"],
    }
  end

  describe "::tag_info", :needs_network do
    it "returns the Git tags for the provided remote URL that match the regex provided" do
      expect(git.tag_info(git_url, regexes[:standard])).not_to be_empty
    end
  end

  describe "::preprocess_url" do
    let(:github_git_url_with_extension) { "https://github.com/Homebrew/brew.git" }

    it "returns the unmodified URL for an unparsable URL" do
      # Modeled after the `head` URL in the `ncp` formula
      expect(git.preprocess_url(":something:cvs:@cvs.brew.sh:/cvs"))
        .to eq(":something:cvs:@cvs.brew.sh:/cvs")
    end

    it "returns the unmodified URL for a GitHub URL ending in .git" do
      expect(git.preprocess_url(github_git_url_with_extension))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub URL not ending in .git" do
      expect(git.preprocess_url("https://github.com/Homebrew/brew"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the unmodified URL for a GitHub /releases/latest URL" do
      expect(git.preprocess_url("https://github.com/Homebrew/brew/releases/latest"))
        .to eq("https://github.com/Homebrew/brew/releases/latest")
    end

    it "returns the Git repository URL for a GitHub AWS URL" do
      expect(git.preprocess_url("https://github.s3.amazonaws.com/downloads/Homebrew/brew/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a github.com/downloads/... URL" do
      expect(git.preprocess_url("https://github.com/downloads/Homebrew/brew/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub tag archive URL" do
      expect(git.preprocess_url("https://github.com/Homebrew/brew/archive/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub release archive URL" do
      expect(git.preprocess_url("https://github.com/Homebrew/brew/releases/download/1.0.0/brew-1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a gitlab.com archive URL" do
      expect(git.preprocess_url("https://gitlab.com/Homebrew/brew/-/archive/1.0.0/brew-1.0.0.tar.gz"))
        .to eq("https://gitlab.com/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a self-hosted GitLab archive URL" do
      expect(git.preprocess_url("https://brew.sh/Homebrew/brew/-/archive/1.0.0/brew-1.0.0.tar.gz"))
        .to eq("https://brew.sh/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a Codeberg archive URL" do
      expect(git.preprocess_url("https://codeberg.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://codeberg.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a Gitea archive URL" do
      expect(git.preprocess_url("https://gitea.com/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://gitea.com/Homebrew/brew.git")
    end

    it "returns the Git repository URL for an Opendev archive URL" do
      expect(git.preprocess_url("https://opendev.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://opendev.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a tildegit archive URL" do
      expect(git.preprocess_url("https://tildegit.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://tildegit.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a LOL Git archive URL" do
      expect(git.preprocess_url("https://lolg.it/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://lolg.it/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a sourcehut archive URL" do
      expect(git.preprocess_url("https://git.sr.ht/~Homebrew/brew/archive/1.0.0.tar.gz"))
        .to eq("https://git.sr.ht/~Homebrew/brew")
    end
  end

  describe "::match?" do
    it "returns true for a Git repository URL" do
      expect(git.match?(git_url)).to be true
    end

    it "returns false for a non-Git URL" do
      expect(git.match?(non_git_url)).to be false
    end
  end

  describe "::versions_from_tags" do
    it "returns an empty array if tags array is empty" do
      expect(git.versions_from_tags([])).to eq([])
    end

    it "returns an array of version strings when given tags" do
      expect(git.versions_from_tags(tags[:normal])).to eq(versions[:default])
      expect(git.versions_from_tags(tags[:normal], regexes[:standard])).to eq(versions[:standard_regex])
      expect(git.versions_from_tags(tags[:normal], regexes[:brew])).to eq(versions[:brew_regex])
    end

    it "returns an array of version strings when given tags and a block" do
      # Returning a string from block, default strategy regex
      expect(git.versions_from_tags(tags[:normal]) { versions[:default].first }).to eq([versions[:default].first])

      # Returning an array of strings from block, default strategy regex
      expect(
        git.versions_from_tags(tags[:hyphens]) do |tags, regex|
          tags.map { |tag| tag[regex, 1]&.tr("-", ".") }
        end,
      ).to eq(versions[:default])

      # Returning an array of strings from block, explicit regex
      expect(
        git.versions_from_tags(tags[:hyphens], regexes[:hyphens]) do |tags, regex|
          tags.map { |tag| tag[regex, 1]&.tr("-", ".") }
        end,
      ).to eq(versions[:standard_regex])

      expect(git.versions_from_tags(tags[:hyphens]) { "1.2.3" }).to eq(["1.2.3"])
    end

    it "allows a nil return from a block" do
      expect(git.versions_from_tags(tags[:normal]) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { git.versions_from_tags(tags[:normal]) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
