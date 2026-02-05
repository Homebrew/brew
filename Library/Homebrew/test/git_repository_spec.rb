# frozen_string_literal: true

require "git_repository"

RSpec.describe GitRepository do
  subject(:git_repo) { described_class.new(clone_path) }

  let(:branch_name) { "main" }
  let(:tag_name) { branch_name }
  let(:repo_root) { mktmpdir }
  let(:remote_path) { repo_root/"origin.git" }
  let(:work_path) { repo_root/"work" }
  let(:clone_path) { repo_root/"clone" }

  before do
    safe_system Utils::Git.git, "-c", "init.defaultBranch=#{branch_name}", "init", "--bare", remote_path

    work_path.mkpath
    work_path.cd do
      safe_system Utils::Git.git, "-c", "init.defaultBranch=#{branch_name}", "init"
      Pathname("README.md").write("README")
      safe_system Utils::Git.git, "add", "README.md"
      safe_system Utils::Git.git, "commit", "-m", "init"
      safe_system Utils::Git.git, "remote", "add", "origin", remote_path
      safe_system Utils::Git.git, "push", "-u", "origin", "refs/heads/#{branch_name}:refs/heads/#{branch_name}"
      safe_system Utils::Git.git, "tag", tag_name
      safe_system Utils::Git.git, "push", "origin", "refs/tags/#{tag_name}"
    end

    remote_path.cd do
      safe_system Utils::Git.git, "symbolic-ref", "HEAD", "refs/heads/#{branch_name}"
    end

    safe_system Utils::Git.git, "clone", remote_path, clone_path
    clone_path.cd do
      safe_system Utils::Git.git, "remote", "set-head", "origin", "--auto"
    end
  end

  describe "when the origin has a branch and tag with the same name" do
    it "disambiguates branch_name, origin_branch_name, and default_origin_branch?" do
      expect(git_repo.branch_name).to eq(branch_name)
      expect(git_repo.origin_branch_name).to eq(branch_name)
      expect(git_repo.default_origin_branch?).to be true

      clone_path.cd do
        safe_system Utils::Git.git, "checkout", "-b", "feature"
      end

      expect(git_repo.default_origin_branch?).to be false
    end

    it "returns HEAD when detached at a tag" do
      clone_path.cd do
        safe_system Utils::Git.git, "checkout", "refs/tags/#{tag_name}"
      end

      expect(git_repo.branch_name).to eq("HEAD")
    end

    it "disambiguates branch_name when refs/stash exists" do
      clone_path.cd do
        safe_system Utils::Git.git, "checkout", "-b", "stash"
        Pathname("README.md").write("README stash")
        safe_system Utils::Git.git, "stash", "--include-untracked"
      end

      expect(git_repo.branch_name).to eq("stash")
    end

    it "preserves branch names starting with heads/" do
      clone_path.cd do
        safe_system Utils::Git.git, "checkout", "-b", "heads/feature"
      end

      expect(git_repo.branch_name).to eq("heads/feature")
    end

    it "raises on unexpected ref prefixes" do
      allow(git_repo).to receive(:popen_git)
        .with("rev-parse", "--symbolic-full-name", "HEAD", safe: false)
        .and_return("refs/tags/#{tag_name}")
      allow(git_repo).to receive(:popen_git)
        .with("symbolic-ref", "-q", "refs/remotes/origin/HEAD")
        .and_return("refs/tags/#{tag_name}")

      expect { git_repo.branch_name }.to raise_error(RuntimeError, /Unexpected HEAD ref/)
      expect { git_repo.origin_branch_name }.to raise_error(RuntimeError, %r{Unexpected origin/HEAD ref})
    end
  end
end
