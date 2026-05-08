# typed: false
# frozen_string_literal: true

require "dev-cmd/pr-pull"
require "utils/git"
require "tap"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::DevCmd::PrPull do
  include FileUtils

  let(:pr_pull) { described_class.new(["foo"]) }
  let(:formula_rebuild) do
    <<~EOS
      class Foo < Formula
        desc "Helpful description"
        url "https://brew.sh/foo-1.0.tgz"
      end
    EOS
  end
  let(:formula_revision) do
    <<~EOS
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        revision 1
      end
    EOS
  end
  let(:formula_version) do
    <<~EOS
      class Foo < Formula
        url "https://brew.sh/foo-2.0.tgz"
      end
    EOS
  end
  let(:formula) do
    <<~EOS
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
      end
    EOS
  end
  let(:cask_rebuild) do
    <<~EOS
      cask "food" do
        desc "Helpful description"
        version "1.0"
        sha256 "a"
        url "https://brew.sh/food-\#{version}.tgz"
      end
    EOS
  end
  let(:cask_checksum) do
    <<~EOS
      cask "food" do
        desc "Helpful description"
        version "1.0"
        sha256 "b"
        url "https://brew.sh/food-\#{version}.tgz"
      end
    EOS
  end
  let(:cask_version) do
    <<~EOS
      cask "food" do
        version "2.0"
        sha256 "a"
        url "https://brew.sh/food-\#{version}.tgz"
      end
    EOS
  end
  let(:cask) do
    <<~EOS
      cask "food" do
        version "1.0"
        sha256 "a"
        url "https://brew.sh/food-\#{version}.tgz"
      end
    EOS
  end
  let(:tap) { Tap.fetch("Homebrew", "foo") }
  let(:formula_file) { tap.path/"Formula/foo.rb" }
  let(:cask_file) { tap.cask_dir/"food.rb" }
  let(:path) { Pathname(HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo") }

  it_behaves_like "parseable arguments"

  describe "#autosquash!" do
    it "squashes a formula or cask correctly" do
      secondary_author = "Someone Else <me@example.com>"
      (tap.path/"Formula").mkpath
      formula_file.write(formula)
      cd tap.path do
        safe_system Utils::Git.git, "init"
        safe_system Utils::Git.git, "add", formula_file
        safe_system Utils::Git.git, "commit", "-m", "foo 1.0 (new formula)"
        original_hash = `git rev-parse HEAD`.chomp
        File.write(formula_file, formula_revision)
        safe_system Utils::Git.git, "commit", formula_file, "-m", "revision"
        File.write(formula_file, formula_version)
        safe_system Utils::Git.git, "commit", formula_file, "-m", "version", "--author=#{secondary_author}"
        pr_pull.autosquash!(original_hash, tap:)
        expect(tap.git_repository.commit_message).to include("foo 2.0")
        expect(tap.git_repository.commit_message).to include("Co-authored-by: #{secondary_author}")
      end

      (path/"Casks").mkpath
      cask_file.write(cask)
      cd path do
        safe_system Utils::Git.git, "add", cask_file
        safe_system Utils::Git.git, "commit", "-m", "food 1.0 (new cask)"
        original_hash = `git rev-parse HEAD`.chomp
        File.write(cask_file, cask_rebuild)
        safe_system Utils::Git.git, "commit", cask_file, "-m", "rebuild"
        File.write(cask_file, cask_version)
        safe_system Utils::Git.git, "commit", cask_file, "-m", "version", "--author=#{secondary_author}"
        pr_pull.autosquash!(original_hash, tap:)
        git_repo = GitRepository.new(path)
        expect(git_repo.commit_message).to include("food 2.0")
        expect(git_repo.commit_message).to include("Co-authored-by: #{secondary_author}")
      end
    end
  end

  describe "#signoff!" do
    it "signs off a formula or cask" do
      (tap.path/"Formula").mkpath
      formula_file.write(formula)
      cd tap.path do
        safe_system Utils::Git.git, "init"
        safe_system Utils::Git.git, "add", formula_file
        safe_system Utils::Git.git, "commit", "-m", "foo 1.0 (new formula)"
      end
      pr_pull.signoff!(tap.git_repository)
      expect(tap.git_repository.commit_message).to include("Signed-off-by:")

      (path/"Casks").mkpath
      cask_file.write(cask)
      cd path do
        safe_system Utils::Git.git, "add", cask_file
        safe_system Utils::Git.git, "commit", "-m", "food 1.0 (new cask)"
      end
      pr_pull.signoff!(tap.git_repository)
      expect(tap.git_repository.commit_message).to include("Signed-off-by:")
    end
  end

  describe "#get_package" do
    it "returns a formula" do
      expect(pr_pull.get_package(tap, "foo", formula_file, formula)).to be_a(Formula)
    end

    it "returns nil for an unknown formula" do
      expect(pr_pull.get_package(tap, "foo", formula_file, "")).to be_nil
    end

    it "returns a cask" do
      expect(pr_pull.get_package(tap, "foo", cask_file, cask)).to be_a(Cask::Cask)
    end

    it "returns nil for an unknown cask" do
      expect(pr_pull.get_package(tap, "foo", cask_file, "")).to be_nil
    end
  end

  describe "#separate_commit_message" do
    it "separates standard -by: trailers" do
      message = "Update foo\n\nSome body text.\n\nCo-authored-by: Alice <a@b.com>\nSigned-off-by: Bob <b@b.com>\n"
      subject, body, trailers = pr_pull.separate_commit_message(message)
      expect(subject).to eq("Update foo")
      expect(body).to eq("Some body text.")
      expect(trailers).to include("Co-authored-by: Alice <a@b.com>")
      expect(trailers).to include("Signed-off-by: Bob <b@b.com>")
    end

    it "separates non-by trailers like Closes: and Fixes:" do
      message = "Fix bug\n\nBody here.\n\nCloses: #123\nFixes: #456\nReviewed-by: Carol <c@c.com>\n"
      subject, body, trailers = pr_pull.separate_commit_message(message)
      expect(subject).to eq("Fix bug")
      expect(body).to eq("Body here.")
      expect(trailers).to include("Closes: #123")
      expect(trailers).to include("Fixes: #456")
      expect(trailers).to include("Reviewed-by: Carol <c@c.com>")
    end

    it "does not extract trailer-like text from mid-body" do
      message = "Subject\n\nSome text.\nCloses: #99\nMore text.\n\nCo-authored-by: D <d@d.com>\n"
      subject, body, trailers = pr_pull.separate_commit_message(message)
      expect(subject).to eq("Subject")
      expect(body).to include("Closes: #99")
      expect(body).to include("More text.")
      expect(trailers).to eq("Co-authored-by: D <d@d.com>")
    end

    it "returns empty trailers when there are none" do
      message = "Subject\n\nJust a body with no trailers.\n"
      subject, body, trailers = pr_pull.separate_commit_message(message)
      expect(subject).to eq("Subject")
      expect(body).to eq("Just a body with no trailers.")
      expect(trailers).to eq("")
    end

    it "handles empty and blank messages" do
      expect(pr_pull.separate_commit_message("")).to eq(["", "", ""])
      subject, body, trailers = pr_pull.separate_commit_message("Subject only\n")
      expect(subject).to eq("Subject only")
      expect(body).to eq("")
      expect(trailers).to eq("")
    end
  end

  describe "#determine_bump_subject" do
    it "correctly bumps a new formula" do
      expect(pr_pull.determine_bump_subject("", formula, formula_file)).to eq("foo 1.0 (new formula)")
    end

    it "correctly bumps a new cask" do
      expect(pr_pull.determine_bump_subject("", cask, cask_file)).to eq("food 1.0 (new cask)")
    end

    it "correctly bumps a formula version" do
      expect(pr_pull.determine_bump_subject(formula, formula_version, formula_file)).to eq("foo 2.0")
    end

    it "correctly bumps a cask version" do
      expect(pr_pull.determine_bump_subject(cask, cask_version, cask_file)).to eq("food 2.0")
    end

    it "correctly bumps a cask checksum" do
      expect(pr_pull.determine_bump_subject(cask, cask_checksum, cask_file)).to eq("food: checksum update")
    end

    it "correctly bumps a formula revision with reason" do
      expect(pr_pull.determine_bump_subject(
               formula, formula_revision, formula_file, reason: "for fun"
             )).to eq("foo: revision for fun")
    end

    it "correctly bumps a formula rebuild" do
      expect(pr_pull.determine_bump_subject(formula, formula_rebuild, formula_file)).to eq("foo: rebuild")
    end

    it "correctly bumps a formula deletion" do
      expect(pr_pull.determine_bump_subject(formula, "", formula_file)).to eq("foo: delete")
    end

    it "correctly bumps a cask deletion" do
      expect(pr_pull.determine_bump_subject(cask, "", cask_file)).to eq("food: delete")
    end
  end
end
