# frozen_string_literal: true

require "dev-cmd/pr-pull"
require "utils/git"
require "tap"
require "cmd/shared_examples/args_parse"

describe "brew pr-pull" do
  it_behaves_like "parseable arguments"

  describe Homebrew do
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
    let(:path) { Pathname(Tap::TAP_DIRECTORY/"homebrew/homebrew-foo") }

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
          described_class.autosquash!(original_hash, tap: tap)
          expect(tap.git_repo.commit_message).to include("foo 2.0")
          expect(tap.git_repo.commit_message).to include("Co-authored-by: #{secondary_author}")
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
          described_class.autosquash!(original_hash, tap: tap)
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
        described_class.signoff!(tap.git_repo)
        expect(tap.git_repo.commit_message).to include("Signed-off-by:")

        (path/"Casks").mkpath
        cask_file.write(cask)
        cd path do
          safe_system Utils::Git.git, "add", cask_file
          safe_system Utils::Git.git, "commit", "-m", "food 1.0 (new cask)"
        end
        described_class.signoff!(tap.git_repo)
        expect(tap.git_repo.commit_message).to include("Signed-off-by:")
      end
    end

    describe "#get_package" do
      it "returns a formula" do
        expect(described_class.get_package(tap, "foo", formula_file, formula)).to be_a(Formula)
      end

      it "returns nil for an unknown formula" do
        expect(described_class.get_package(tap, "foo", formula_file, "")).to be_nil
      end

      it "returns a cask" do
        expect(described_class.get_package(tap, "foo", cask_file, cask)).to be_a(Cask::Cask)
      end

      it "returns nil for an unknown cask" do
        expect(described_class.get_package(tap, "foo", cask_file, "")).to be_nil
      end
    end

    describe "#determine_bump_subject" do
      it "correctly bumps a new formula" do
        expect(described_class.determine_bump_subject("", formula, formula_file)).to eq("foo 1.0 (new formula)")
      end

      it "correctly bumps a new cask" do
        expect(described_class.determine_bump_subject("", cask, cask_file)).to eq("food 1.0 (new cask)")
      end

      it "correctly bumps a formula version" do
        expect(described_class.determine_bump_subject(formula, formula_version, formula_file)).to eq("foo 2.0")
      end

      it "correctly bumps a cask version" do
        expect(described_class.determine_bump_subject(cask, cask_version, cask_file)).to eq("food 2.0")
      end

      it "correctly bumps a cask checksum" do
        expect(described_class.determine_bump_subject(cask, cask_checksum, cask_file)).to eq("food: checksum update")
      end

      it "correctly bumps a formula revision with reason" do
        expect(described_class.determine_bump_subject(
                 formula, formula_revision, formula_file, reason: "for fun"
               )).to eq("foo: revision for fun")
      end

      it "correctly bumps a formula rebuild" do
        expect(described_class.determine_bump_subject(formula, formula_rebuild, formula_file)).to eq("foo: rebuild")
      end

      it "correctly bumps a formula deletion" do
        expect(described_class.determine_bump_subject(formula, "", formula_file)).to eq("foo: delete")
      end

      it "correctly bumps a cask deletion" do
        expect(described_class.determine_bump_subject(cask, "", cask_file)).to eq("food: delete")
      end
    end
  end
end
