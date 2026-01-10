# frozen_string_literal: true

require "cmd/source"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Source do
  it_behaves_like "parseable arguments"

  it "opens the Homebrew repo when no formula is specified", :integration_test do
    expect { brew "source", "HOMEBREW_BROWSER" => "echo" }
      .to output(%r{https://github\.com/Homebrew/brew}).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  describe "#github_repo_url" do
    it "extracts repository URL from GitHub URL" do
      expect(described_class.new([]).send(:github_repo_url, "https://github.com/Homebrew/brew.git"))
        .to eq("https://github.com/Homebrew/brew")
    end

    it "handles GitHub archive URLs" do
      expect(described_class.new([]).send(:github_repo_url, "https://github.com/Homebrew/testball/archive/refs/tags/v0.1.tar.gz"))
        .to eq("https://github.com/Homebrew/testball")
    end

    it "returns nil for non-GitHub URLs" do
      expect(described_class.new([]).send(:github_repo_url, "https://example.com/repo.git"))
        .to be_nil
    end
  end

  describe "#gitlab_repo_url" do
    it "extracts repository URL from GitLab URL with nested groups" do
      expect(described_class.new([]).send(:gitlab_repo_url, "https://gitlab.com/group/subgroup/project/-/archive/v1.0/project-v1.0.tar.gz"))
        .to eq("https://gitlab.com/group/subgroup/project")
    end

    it "handles GitLab .git URLs" do
      expect(described_class.new([]).send(:gitlab_repo_url, "https://gitlab.com/user/repo.git"))
        .to eq("https://gitlab.com/user/repo")
    end

    it "returns nil for non-GitLab URLs" do
      expect(described_class.new([]).send(:gitlab_repo_url, "https://example.com/repo.git"))
        .to be_nil
    end
  end

  describe "#bitbucket_repo_url" do
    it "extracts repository URL from Bitbucket URL" do
      expect(described_class.new([]).send(:bitbucket_repo_url, "https://bitbucket.org/user/repo/get/v1.0.tar.gz"))
        .to eq("https://bitbucket.org/user/repo")
    end

    it "handles Bitbucket .git URLs" do
      expect(described_class.new([]).send(:bitbucket_repo_url, "https://bitbucket.org/user/repo.git"))
        .to eq("https://bitbucket.org/user/repo")
    end

    it "returns nil for non-Bitbucket URLs" do
      expect(described_class.new([]).send(:bitbucket_repo_url, "https://example.com/repo.git"))
        .to be_nil
    end
  end

  describe "#codeberg_repo_url" do
    it "extracts repository URL from Codeberg URL" do
      expect(described_class.new([]).send(:codeberg_repo_url, "https://codeberg.org/user/repo/archive/v1.0.tar.gz"))
        .to eq("https://codeberg.org/user/repo")
    end

    it "handles Codeberg .git URLs" do
      expect(described_class.new([]).send(:codeberg_repo_url, "https://codeberg.org/user/repo.git"))
        .to eq("https://codeberg.org/user/repo")
    end

    it "returns nil for non-Codeberg URLs" do
      expect(described_class.new([]).send(:codeberg_repo_url, "https://example.com/repo.git"))
        .to be_nil
    end
  end

  describe "#sourcehut_repo_url" do
    it "extracts repository URL from SourceHut URL" do
      expect(described_class.new([]).send(:sourcehut_repo_url, "https://git.sr.ht/~user/repo/archive/v1.0.tar.gz"))
        .to eq("https://sr.ht/~user/repo")
    end

    it "handles sr.ht URLs without git subdomain" do
      expect(described_class.new([]).send(:sourcehut_repo_url, "https://sr.ht/~user/repo"))
        .to eq("https://sr.ht/~user/repo")
    end

    it "returns nil for non-SourceHut URLs" do
      expect(described_class.new([]).send(:sourcehut_repo_url, "https://example.com/repo.git"))
        .to be_nil
    end
  end

  describe "#url_to_repo" do
    it "returns GitHub repo URL for GitHub URLs" do
      expect(described_class.new([]).send(:url_to_repo, "https://github.com/Homebrew/brew"))
        .to eq("https://github.com/Homebrew/brew")
    end

    it "returns GitLab repo URL for GitLab URLs" do
      expect(described_class.new([]).send(:url_to_repo, "https://gitlab.com/user/repo.git"))
        .to eq("https://gitlab.com/user/repo")
    end

    it "returns nil for unsupported URLs" do
      expect(described_class.new([]).send(:url_to_repo, "https://example.com/repo.tar.gz"))
        .to be_nil
    end
  end
end
