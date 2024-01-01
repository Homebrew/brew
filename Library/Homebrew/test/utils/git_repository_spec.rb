# frozen_string_literal: true

require "utils/git_repository"

describe Utils do
  shared_examples "git_repository helper function" do |method_name|
    context "when directory is not a Git repository" do
      it "returns nil if `safe` parameter is `false`" do
        expect(described_class.public_send(method_name, TEST_TMPDIR, safe: false)).to be_nil
      end

      it "raises an error if `safe` parameter is `true`" do
        expect { described_class.public_send(method_name, TEST_TMPDIR, safe: true) }
          .to raise_error("Not a Git repository: #{TEST_TMPDIR}")
      end
    end

    context "when Git is unavailable" do
      before do
        allow(Utils::Git).to receive(:available?).and_return(false)
      end

      it "returns nil if `safe` parameter is `false`" do
        expect(described_class.public_send(method_name, HOMEBREW_CACHE, safe: false)).to be_nil
      end

      it "raises an error if `safe` parameter is `true`" do
        expect { described_class.public_send(method_name, HOMEBREW_CACHE, safe: true) }
          .to raise_error("Git is unavailable")
      end
    end
  end

  before do
    HOMEBREW_CACHE.cd do
      system "git", "init"
      Pathname("README.md").write("README")
      system "git", "add", "README.md"
      system "git", "commit", "-m", commit_message
      system "git", "checkout", "-b", branch_name
    end
  end

  let(:commit_message) { "File added" }
  let(:branch_name) { "test-branch" }

  let(:head_revision) { HOMEBREW_CACHE.cd { `git rev-parse HEAD`.chomp } }
  let(:short_head_revision) { HOMEBREW_CACHE.cd { `git rev-parse --short HEAD`.chomp } }

  describe "::git_head" do
    it "returns the revision at HEAD" do
      expect(described_class.git_head(HOMEBREW_CACHE)).to eq(head_revision)
      expect(described_class.git_head(HOMEBREW_CACHE, length: 5)).to eq(head_revision[0...5])
      HOMEBREW_CACHE.cd do
        expect(described_class.git_head).to eq(head_revision)
        expect(described_class.git_head(length: 5)).to eq(head_revision[0...5])
      end
    end

    include_examples "git_repository helper function", :git_head
  end

  describe "::git_short_head" do
    it "returns the short revision at HEAD" do
      expect(described_class.git_short_head(HOMEBREW_CACHE)).to eq(short_head_revision)
      expect(described_class.git_short_head(HOMEBREW_CACHE, length: 5)).to eq(head_revision[0...5])
      HOMEBREW_CACHE.cd do
        expect(described_class.git_short_head).to eq(short_head_revision)
        expect(described_class.git_short_head(length: 5)).to eq(head_revision[0...5])
      end
    end

    include_examples "git_repository helper function", :git_short_head
  end

  describe "::git_branch" do
    include_examples "git_repository helper function", :git_branch

    it "returns the current Git branch" do
      expect(described_class.git_branch(HOMEBREW_CACHE)).to eq(branch_name)
      HOMEBREW_CACHE.cd do
        expect(described_class.git_branch).to eq(branch_name)
      end
    end
  end

  describe "::git_commit_message" do
    include_examples "git_repository helper function", :git_commit_message

    it "returns the commit message of HEAD" do
      expect(described_class.git_commit_message(HOMEBREW_CACHE)).to eq(commit_message)
      expect(described_class.git_commit_message(HOMEBREW_CACHE, commit: head_revision)).to eq(commit_message)
      HOMEBREW_CACHE.cd do
        expect(described_class.git_commit_message).to eq(commit_message)
        expect(described_class.git_commit_message(commit: head_revision)).to eq(commit_message)
      end
    end
  end
end
