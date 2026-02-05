# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Git do
  subject(:git) { described_class }

  let(:git_url) { "https://github.com/Homebrew/brew.git" }
  let(:non_git_url) { "https://brew.sh/test" }

  let(:regexes) do
    {
      standard: /^v?(\d+(?:\.\d+)+)$/i,
      hyphens:  /^v?(\d+(?:[.-]\d+)+)$/i,
      brew:     %r{^brew/v?(\d+(?:\.\d+)+)$}i,
    }
  end

  let(:content) do
    normal = <<~EOS
      e0f1758045b8194f77a43050ca433cbe928f27fb\trefs/tags/brew/1.2
      5a45d5c9e39da019b2feaf63a1321e2f0336769c\trefs/tags/brew/1.2.1
      81426bcda28e391b29770747ecd86bf8324d2441\trefs/tags/brew/1.2.2
      50631d8ae8885d6b3a51814f4529c0b2e5d424fa\trefs/tags/brew/1.2.3
      cd58e678c52ef269d2ba5153a9dd0f83864ab7b4\trefs/tags/brew/1.2.4^{}
      db2b77f42b1c1fa7bb74f13ce798290084aa89f3\trefs/tags/1.2.5
    EOS
    hyphens = normal.tr(".", "-")

    {
      normal:,
      hyphens:,
    }
  end

  let(:tags) do
    {
      normal:  ["brew/1.2", "brew/1.2.1", "brew/1.2.2", "brew/1.2.3", "brew/1.2.4", "1.2.5"],
      hyphens: ["brew/1-2", "brew/1-2-1", "brew/1-2-2", "brew/1-2-3", "brew/1-2-4", "1-2-5"],
    }
  end

  let(:matches) do
    {
      default:        ["1.2", "1.2.1", "1.2.2", "1.2.3", "1.2.4", "1.2.5"],
      standard_regex: ["1.2.5"],
      brew_regex:     ["1.2", "1.2.1", "1.2.2", "1.2.3", "1.2.4"],
    }
  end

  let(:messages) do
    [
      "remote: Support for password authentication was removed on August 13, 2021.",
      "fatal: Authentication failed for '#{git_url}'",
    ]
  end

  describe "::preprocess_url" do
    before do
      # Clear the processed URL cache before each test, to ensure that we're
      # properly testing the method's processing logic.
      git.instance_variable_set(:@processed_urls, {})
    end

    let(:github_git_url_with_extension) { "https://github.com/Homebrew/brew.git" }

    it "returns a cached value if provided URL has already been processed" do
      # This uses an unrealistic value to make sure that we are receiving a
      # cached value from `@processed_urls` and not a newly-processed URL.
      cached_value = "CACHED"
      git.instance_variable_set(:@processed_urls, { non_git_url => cached_value })
      expect(git.preprocess_url(non_git_url)).to eq(cached_value)
    end

    it "returns the unmodified URL for an unparsable URL" do
      expect(git.preprocess_url(":something:cvs:@cvs.brew.sh:/cvs"))
        .to eq(":something:cvs:@cvs.brew.sh:/cvs")
    end

    it "returns the unmodified URL for a URL without a host" do
      expect(git.preprocess_url("/test/")).to eq("/test/")
    end

    it "returns the unmodified URL for a URL without a path" do
      expect(git.preprocess_url("https://example.com"))
        .to eq("https://example.com")
    end

    it "returns the unmodified URL for a URL without a host or path" do
      expect(git.preprocess_url("")).to eq("")
    end

    it "returns the unmodified URL for a GitHub URL ending in .git" do
      expect(git.preprocess_url(github_git_url_with_extension))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub URL not ending in .git" do
      # We run a test twice to exercise the `processed_url` early return.
      # It doesn't matter which test we do this with, as long as the URL is
      # modified and stored in `@processed_urls`.
      2.times do
        expect(git.preprocess_url("https://github.com/Homebrew/brew"))
          .to eq(github_git_url_with_extension)
      end
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

    it "returns the unmodified URL for a Gitea /releases/latest URL" do
      expect(git.preprocess_url("https://gitea.com/Homebrew/brew/releases/latest"))
        .to eq("https://gitea.com/Homebrew/brew/releases/latest")
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

  describe "::ls_remote_tags" do
    it "returns the Git tags for the provided remote URL", :needs_network do
      expect(git.ls_remote_tags(git_url)).not_to be_empty
    end

    it "returns a hash containing fetched content from `stdout`" do
      allow(git).to receive(:system_command)
        .and_return([content[:normal], nil, nil])
      expect(git.ls_remote_tags(git_url)).to eq({ content: content[:normal] })
    end

    it "returns a hash containing error messages from `stderr`" do
      allow(git).to receive(:system_command)
        .and_return([nil, messages.join("\n"), nil])
      expect(git.ls_remote_tags(git_url)).to eq({ messages: })
    end

    it "returns a hash containing fetched content and error messages when both `stdout` and `stderr` are present" do
      allow(git).to receive(:system_command)
        .and_return([content[:normal], messages.join("\n"), nil])
      expect(git.ls_remote_tags(git_url)).to eq({ content: content[:normal], messages: })
    end

    it "returns a blank hash if neither `stdout` nor `stderr` are present" do
      allow(git).to receive(:system_command).and_return([nil, nil, nil])
      expect(git.ls_remote_tags(git_url)).to eq({})
    end
  end

  describe "::tags_from_content" do
    it "returns an empty array if content string doesn't contain parseable text" do
      expect(git.tags_from_content("")).to eq([])
    end

    it "returns an array of tag strings when given content" do
      expect(git.tags_from_content(content[:normal])).to eq(tags[:normal])
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if content contains no tags" do
      expect(git.versions_from_content("")).to eq([])
    end

    it "returns an array of version strings when given content" do
      expect(git.versions_from_content(content[:normal])).to eq(matches[:default])
      expect(git.versions_from_content(content[:normal], regexes[:standard])).to eq(matches[:standard_regex])
      expect(git.versions_from_content(content[:normal], regexes[:brew])).to eq(matches[:brew_regex])
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block, default strategy regex
      expect(git.versions_from_content(content[:normal]) { matches[:default].first }).to eq([matches[:default].first])

      # Returning an array of strings from block, default strategy regex
      expect(
        git.versions_from_content(content[:hyphens]) do |tags, regex|
          tags.map { |tag| tag[regex, 1]&.tr("-", ".") }
        end,
      ).to eq(matches[:default])

      # Returning an array of strings from block, explicit regex
      expect(
        git.versions_from_content(content[:hyphens], regexes[:hyphens]) do |tags, regex|
          tags.map { |tag| tag[regex, 1]&.tr("-", ".") }
        end,
      ).to eq(matches[:standard_regex])

      expect(git.versions_from_content(content[:hyphens]) { "1.2.3" }).to eq(["1.2.3"])
    end

    it "allows a nil return from a block" do
      expect(git.versions_from_content(content[:normal]) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { git.versions_from_content(content[:normal]) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      base = {
        matches: matches[:brew_regex].to_h { |v| [v, Version.new(v)] },
        regex:   regexes[:brew],
        url:     git_url,
      }
      default = base.merge(matches: {})

      {
        fetched:               base.merge({ content: content[:normal] }),
        fetched_default_regex: {
          matches: matches[:default].to_h { |v| [v, Version.new(v)] },
          regex:   nil,
          url:     git_url,
          content: content[:normal],
        },
        default:,
        cached:                base.merge({ cached: true }),
        cached_default:        default.merge({ cached: true }),
      }
    end

    it "finds versions in fetched content" do
      allow(git).to receive(:ls_remote_tags).and_return({ content: content[:normal] })

      expect(git.find_versions(url: git_url, regex: regexes[:brew]))
        .to eq(match_data[:fetched])
      expect(git.find_versions(url: git_url)).to eq(match_data[:fetched_default_regex])
    end

    it "returns match_data with error messages from ls_remote_tags" do
      error_hash = { messages: }
      allow(git).to receive(:ls_remote_tags).and_return(error_hash)

      expect(git.find_versions(url: git_url, regex: regexes[:brew]))
        .to eq(match_data[:default].merge(error_hash))
    end

    it "finds versions in provided content" do
      expect(git.find_versions(url: git_url, regex: regexes[:brew], provided_content: content[:normal]))
        .to eq(match_data[:cached])

      # A regex should be passed into a `strategy` block (instead of using a
      # regex literal within the `strategy` block) but we're using this
      # approach for the sake of testing.
      expect(git.find_versions(url: git_url, provided_content: content[:normal]) do |tags|
        tags.map { |tag| tag[%r{^brew/v?(\d+(?:\.\d+)+)$}i, 1] }
      end).to eq(match_data[:cached].merge({ regex: nil }))
    end

    it "returns default match_data when url is blank" do
      expect(git.find_versions(url: "", regex: regexes[:brew], provided_content: content[:normal]))
        .to eq({ matches: {}, regex: regexes[:brew], url: "" })
    end

    it "returns default match_data when content doesn't contain tags" do
      expect(git.find_versions(url: git_url, regex: regexes[:brew], provided_content: "abc"))
        .to eq(match_data[:cached_default])
    end

    it "returns default match_data when content is blank" do
      expect(git.find_versions(url: git_url, regex: regexes[:brew], provided_content: ""))
        .to eq(match_data[:cached_default])
    end

    it "omits tag values that produce a `TypeError` when creating a `Version` object" do
      # This overrides the `versions_from_content` return value to also include
      # non-string values that will produce a `TypeError` for `Version::new`.
      # This shouldn't happen under normal circumstances but this allows us
      # to test this safeguard.
      allow(git).to receive(:versions_from_content).and_return([1, *matches[:brew_regex], nil])

      expect(git.find_versions(url: git_url, regex: regexes[:brew], provided_content: content[:normal]))
        .to eq(match_data[:cached])
    end
  end
end
