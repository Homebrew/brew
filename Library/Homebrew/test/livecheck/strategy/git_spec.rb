# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Git do
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
