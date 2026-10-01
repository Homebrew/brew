# typed: true
# frozen_string_literal: true

require "system_command"

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
    SystemCommand.safe_system Utils::Git.git, "-c", "init.defaultBranch=#{branch_name}", "init", "--bare", remote_path

    work_path.mkpath
    work_path.cd do
      SystemCommand.safe_system Utils::Git.git, "-c", "init.defaultBranch=#{branch_name}", "init"
      Pathname("README.md").write("README")
      SystemCommand.safe_system Utils::Git.git, "add", "README.md"
      SystemCommand.safe_system Utils::Git.git, "commit", "-m", "init"
      SystemCommand.safe_system Utils::Git.git, "remote", "add", "origin", remote_path
      SystemCommand.safe_system Utils::Git.git, "push", "-u", "origin",
                                "refs/heads/#{branch_name}:refs/heads/#{branch_name}"
      SystemCommand.safe_system Utils::Git.git, "tag", tag_name
      SystemCommand.safe_system Utils::Git.git, "push", "origin", "refs/tags/#{tag_name}"
    end

    remote_path.cd do
      SystemCommand.safe_system Utils::Git.git, "symbolic-ref", "HEAD", "refs/heads/#{branch_name}"
    end

    SystemCommand.safe_system Utils::Git.git, "clone", remote_path, clone_path
    clone_path.cd do
      SystemCommand.safe_system Utils::Git.git, "remote", "set-head", "origin", "--auto"
    end
  end

  it "reads the origin URL when the global Git config is unusable" do
    global_config = repo_root/"global.gitconfig"
    global_config.write("[broken\n")

    with_env(GIT_CONFIG_GLOBAL: global_config.to_s) do
      expect(git_repo.origin_url).to eq(remote_path.to_s)
    end
  end

  describe "#shallow?" do
    let(:shallow_path) { repo_root/"shallow" }
    let(:worktree_path) { repo_root/"shallow-worktree" }

    before do
      SystemCommand.safe_system Utils::Git.git, "clone", "--depth", "1", "file://#{remote_path}", shallow_path
      SystemCommand.safe_system Utils::Git.git, "-C", shallow_path, "worktree", "add", "--detach", worktree_path
    end

    it "detects a shallow clone through its linked worktree but not a full clone" do
      expect([
        described_class.new(shallow_path).shallow?,
        described_class.new(worktree_path).shallow?,
        git_repo.shallow?,
      ]).to eq [true, true, false]
    end
  end

  describe "#origin_url" do
    it "reads the origin URL from .git/config without spawning Git" do
      allow(git_repo).to receive(:popen_git).and_raise("Git should not be spawned")
      expect(git_repo.origin_url).to eq(remote_path.to_s)
    end

    it "falls back to Git when the config has more than one origin URL" do
      other_url = "https://brew.sh/other.git"
      config = clone_path/".git/config"
      config.write(%Q(#{config.read}[remote "origin"]\n\turl = #{other_url}\n))
      expect(git_repo.origin_url).to eq(other_url)
    end
  end

  describe "#head_info" do
    it "returns the HEAD commit hash, relative commit time and branch name in one Git invocation" do
      expect(git_repo.head_info).to eq([git_repo.head_ref, git_repo.last_committed, branch_name])

      clone_path.cd do
        SystemCommand.safe_system Utils::Git.git, "checkout", "--quiet", "--detach"
      end
      expect(git_repo.head_info[2]).to eq("HEAD")

      expect(described_class.new(repo_root/"nonexistent").head_info).to eq([nil, nil, nil])
    end
  end

  describe "when the origin has a branch and tag with the same name" do
    it "disambiguates branch_name, origin_branch_name, and default_origin_branch?" do
      expect(git_repo.branch_name).to eq(branch_name)
      expect(git_repo.origin_branch_name).to eq(branch_name)
      expect(git_repo.default_origin_branch?).to be true

      clone_path.cd do
        SystemCommand.safe_system Utils::Git.git, "checkout", "-b", "feature"
      end

      expect(git_repo.default_origin_branch?).to be false
    end

    it "returns HEAD when detached at a tag" do
      clone_path.cd do
        SystemCommand.safe_system Utils::Git.git, "checkout", "refs/tags/#{tag_name}"
      end

      expect(git_repo.branch_name).to eq("HEAD")
    end

    it "disambiguates branch_name when refs/stash exists" do
      clone_path.cd do
        SystemCommand.safe_system Utils::Git.git, "checkout", "-b", "stash"
        Pathname("README.md").write("README stash")
        SystemCommand.safe_system Utils::Git.git, "stash", "--include-untracked"
      end

      expect(git_repo.branch_name).to eq("stash")
    end

    it "preserves branch names starting with heads/" do
      clone_path.cd do
        SystemCommand.safe_system Utils::Git.git, "checkout", "-b", "heads/feature"
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
