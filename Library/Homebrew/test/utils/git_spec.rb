# frozen_string_literal: true

require "utils/git"

RSpec.describe Utils::Git do
  around do |example|
    described_class.clear_available_cache
    example.run
  ensure
    described_class.clear_available_cache
  end

  before do
    git = HOMEBREW_SHIMS_PATH/"shared/git"

    HOMEBREW_CACHE.cd do
      system git, "init"

      File.write("README.md", "README")
      system git, "add", HOMEBREW_CACHE/"README.md"
      system git, "commit", "-m", "File added"
      @h1 = `git rev-parse HEAD`

      File.write("README.md", "# README")
      system git, "add", HOMEBREW_CACHE/"README.md"
      system git, "commit", "-m", "written to File"
      @h2 = `git rev-parse HEAD`

      File.write("LICENSE.txt", "LICENCE")
      system git, "add", HOMEBREW_CACHE/"LICENSE.txt"
      system git, "commit", "-m", "File added"
      @h3 = `git rev-parse HEAD`

      File.write("LICENSE.txt", "LICENSE")
      system git, "add", HOMEBREW_CACHE/"LICENSE.txt"
      system git, "commit", "-m", "written to File"

      File.write("LICENSE.txt", "test")
      system git, "add", HOMEBREW_CACHE/"LICENSE.txt"
      system git, "commit", "-m", "written to File"
      @cherry_pick_commit = `git rev-parse HEAD`
      system git, "reset", "--hard", "HEAD^"
    end
  end

  let(:file) { "README.md" }
  # Allow instance variables here for a simpler `before do` block.
  # rubocop:disable RSpec/InstanceVariable
  let(:file_hash_one) { @h1[0..6] }
  let(:file_hash_two) { @h2[0..6] }
  let(:files) { ["README.md", "LICENSE.txt"] }
  let(:files_hash_one) { [@h3[0..6], ["LICENSE.txt"]] }
  let(:files_hash_two) { [@h2[0..6], ["README.md"]] }
  let(:cherry_pick_commit) { @cherry_pick_commit[0..6] }
  # rubocop:enable RSpec/InstanceVariable

  describe "#cherry_pick!" do
    it "can cherry pick a commit" do
      expect(described_class.cherry_pick!(HOMEBREW_CACHE, cherry_pick_commit)).to be_truthy
    end

    it "aborts when cherry picking an existing hash" do
      ENV["GIT_MERGE_VERBOSITY"] = "5" # Consistent output across git versions
      expect do
        described_class.cherry_pick!(HOMEBREW_CACHE, file_hash_one)
      end.to raise_error(ErrorDuringExecution, /Merge conflict in README.md/)
    end
  end

  describe "#last_revision_commit_of_file" do
    it "gives last revision commit when before_commit is nil" do
      expect(
        described_class.last_revision_commit_of_file(HOMEBREW_CACHE, file),
      ).to eq(file_hash_one)
    end

    it "gives revision commit based on before_commit when it is not nil" do
      expect(
        described_class.last_revision_commit_of_file(HOMEBREW_CACHE,
                                                     file,
                                                     before_commit: file_hash_two),
      ).to eq(file_hash_two)
    end
  end

  describe "#file_at_commit" do
    it "returns file contents when file exists" do
      expect(described_class.file_at_commit(HOMEBREW_CACHE, file, file_hash_one)).to eq("README")
    end

    it "returns empty when file doesn't exist" do
      expect(described_class.file_at_commit(HOMEBREW_CACHE, "foo.txt", file_hash_one)).to eq("")
      expect(described_class.file_at_commit(HOMEBREW_CACHE, "LICENSE.txt", file_hash_one)).to eq("")
    end
  end

  describe "#last_revision_commit_of_files" do
    context "when before_commit is nil" do
      it "gives last revision commit" do
        expect(
          described_class.last_revision_commit_of_files(HOMEBREW_CACHE, files),
        ).to eq(files_hash_one)
      end
    end

    context "when before_commit is not nil" do
      it "gives last revision commit" do
        expect(
          described_class.last_revision_commit_of_files(HOMEBREW_CACHE,
                                                        files,
                                                        before_commit: file_hash_two),
        ).to eq(files_hash_two)
      end
    end
  end

  describe "#last_revision_of_file" do
    it "returns last revision of file" do
      expect(
        described_class.last_revision_of_file(HOMEBREW_CACHE,
                                              HOMEBREW_CACHE/file),
      ).to eq("README")
    end

    it "returns last revision of file based on before_commit" do
      expect(
        described_class.last_revision_of_file(HOMEBREW_CACHE, HOMEBREW_CACHE/file,
                                              before_commit: "0..3"),
      ).to eq("# README")
    end
  end

  describe "::available?" do
    it "returns true if git --version command succeeds" do
      expect(described_class).to be_available
    end

    it "returns false if git --version command does not succeed" do
      stub_const("HOMEBREW_SHIMS_PATH", HOMEBREW_PREFIX/"bin/shim")
      expect(described_class).not_to be_available
    end
  end

  describe "::path" do
    it "returns nil when git is not available" do
      stub_const("HOMEBREW_SHIMS_PATH", HOMEBREW_PREFIX/"bin/shim")
      expect(described_class.path).to be_nil
    end

    it "returns path of git when git is available" do
      expect(described_class.path).to end_with("git")
    end
  end

  describe "::version" do
    it "returns nil when git is not available" do
      stub_const("HOMEBREW_SHIMS_PATH", HOMEBREW_PREFIX/"bin/shim")
      expect(described_class.version).to be_nil
    end

    it "returns version of git when git is available" do
      expect(described_class.version).not_to be_nil
    end
  end

  describe "::ensure_installed!" do
    it "returns nil if git already available" do
      expect(described_class.ensure_installed!).to be_nil
    end

    context "when git is not already available" do
      before do
        stub_const("HOMEBREW_SHIMS_PATH", HOMEBREW_PREFIX/"bin/shim")
      end

      it "can't install brewed git if homebrew/core is unavailable" do
        allow_any_instance_of(Pathname).to receive(:directory?).and_return(false)
        expect { described_class.ensure_installed! }.to raise_error("Git is unavailable")
      end

      it "raises error if can't install git" do
        stub_const("HOMEBREW_BREW_FILE", HOMEBREW_PREFIX/"bin/brew")
        expect { described_class.ensure_installed! }.to raise_error("Git is unavailable")
      end

      unless ENV["HOMEBREW_TEST_GENERIC_OS"]
        it "installs git" do
          expect(described_class).to receive(:available?).and_return(false)
          expect(described_class).to receive(:ensure_formula_installed!).with("git")
          expect(described_class).to receive(:available?).and_return(true)

          described_class.ensure_installed!
        end
      end
    end
  end

  describe "::remote_exists?" do
    it "returns true when git is not available" do
      stub_const("HOMEBREW_SHIMS_PATH", HOMEBREW_PREFIX/"bin/shim")
      expect(described_class).to be_remote_exists("blah")
    end

    context "when git is available" do
      it "returns true when git remote exists", :needs_network do
        git = HOMEBREW_SHIMS_PATH/"shared/git"
        url = "https://github.com/Homebrew/homebrew.github.io"
        repo = HOMEBREW_CACHE/"hey"
        repo.mkpath

        repo.cd do
          system git, "init"
          system git, "remote", "add", "origin", url
        end

        expect(described_class).to be_remote_exists(url)
      end

      it "returns false when git remote does not exist" do
        expect(described_class).not_to be_remote_exists("blah")
      end
    end
  end
end
