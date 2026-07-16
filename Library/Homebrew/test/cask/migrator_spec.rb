# typed: false
# frozen_string_literal: true

require "cask/migrator"

RSpec.describe Cask::Migrator do
  describe ".old_tokens_needing_migration" do
    let(:new_cask) { instance_double(Cask::Cask, token: "new-token", old_tokens: ["old-token"]) }

    def setup_installed_cask(dir, token)
      casks_dir = dir/token/".metadata/1.0/20250101000000.000/Casks"
      casks_dir.mkpath
      (casks_dir/"#{token}.rb").write("cask \"#{token}\"\n")
    end

    it "returns old tokens that are still installed in their own Caskroom directory" do
      Dir.mktmpdir do |dir|
        allow(Cask::Caskroom).to receive(:path).and_return(Pathname(dir))
        setup_installed_cask(Pathname(dir), "old-token")

        expect(described_class.old_tokens_needing_migration(new_cask)).to eq(["old-token"])
      end
    end

    it "returns old tokens even when the new cask is installed under its own token" do
      Dir.mktmpdir do |dir|
        allow(Cask::Caskroom).to receive(:path).and_return(Pathname(dir))
        setup_installed_cask(Pathname(dir), "old-token")
        setup_installed_cask(Pathname(dir), "new-token")

        expect(described_class.old_tokens_needing_migration(new_cask)).to eq(["old-token"])
      end
    end

    it "ignores old tokens that have already been migrated" do
      Dir.mktmpdir do |dir|
        allow(Cask::Caskroom).to receive(:path).and_return(Pathname(dir))
        setup_installed_cask(Pathname(dir), "new-token")
        FileUtils.ln_s "new-token", Pathname(dir)/"old-token"

        expect(described_class.old_tokens_needing_migration(new_cask)).to be_empty
      end
    end

    it "removes an empty Caskroom directory for an old token" do
      Dir.mktmpdir do |dir|
        allow(Cask::Caskroom).to receive(:path).and_return(Pathname(dir))
        old_caskroom_path = Pathname(dir)/"old-token"
        old_caskroom_path.mkpath

        expect([described_class.old_tokens_needing_migration(new_cask), old_caskroom_path.exist?])
          .to eq([[], false])
      end
    end
  end

  describe ".migrate_if_needed", :cask do
    let(:old_cask) { Cask::CaskLoader.load(cask_path("local-caffeine")) }
    let(:new_cask) { Cask::CaskLoader.load(cask_path("local-transmission")) }
    let(:old_caskroom_path) { Cask::Caskroom.path/"local-caffeine" }
    let(:appdir) { Pathname(new_cask.config.appdir) }

    # The new cask is renamed from the old cask, but stub this only once both casks are
    # installed so that installing the new cask does not migrate the old cask itself.
    def rename_old_cask_to_new_cask
      allow(new_cask).to receive(:old_tokens).and_return(["local-caffeine"])
    end

    context "when the new cask is not installed" do
      it "moves the old cask to the new token" do
        InstallHelper.stub_cask_installation(old_cask)
        rename_old_cask_to_new_cask

        described_class.migrate_if_needed(new_cask)

        expect([old_caskroom_path.symlink?, new_cask.installed_version])
          .to eq([true, old_cask.version.to_s])
      end
    end

    context "when the new cask is already installed" do
      before do
        Cask::Installer.new(new_cask).install
        Cask::Installer.new(old_cask).install
        rename_old_cask_to_new_cask
      end

      it "uninstalls the old cask" do
        expect { described_class.migrate_if_needed(new_cask) }
          .to output(/Uninstalling Cask local-caffeine/).to_stdout

        expect([
          old_caskroom_path.symlink?,
          (appdir/"Caffeine.app").exist?,
          (appdir/"Transmission.app").exist?,
          new_cask.installed?,
        ]).to eq([true, false, true, true])
      end

      it "does not uninstall the old cask in a dry run" do
        expect { described_class.migrate_if_needed(new_cask, dry_run: true) }
          .to output(/local-transmission is already installed, so local-caffeine would be uninstalled/)
          .to_stdout

        expect([old_caskroom_path.directory?, (appdir/"Caffeine.app").exist?]).to eq([true, true])
      end
    end

    context "when the new cask is already installed and shares an artifact with the old cask" do
      let(:new_cask) { Cask::CaskLoader.load(cask_path("local-caffeine-clone")) }

      before do
        Cask::Installer.new(old_cask).install
        # Both casks install `Caffeine.app`, so the second install has to overwrite it.
        Cask::Installer.new(new_cask, force: true).install
        rename_old_cask_to_new_cask
      end

      it "keeps the shared artifact installed for the new cask" do
        expect { described_class.migrate_if_needed(new_cask) }
          .to output(/Keeping Caffeine.app \(App\) as local-caffeine-clone installs it too/).to_stdout

        expect([
          old_caskroom_path.symlink?,
          (appdir/"Caffeine.app").exist?,
          new_cask.installed?,
        ]).to eq([true, true, true])
      end
    end
  end

  describe "#migrate" do
    let(:old_caskroom_path) { Pathname("/tmp/Caskroom/old-token") }
    let(:new_caskroom_path) { Pathname("/tmp/Caskroom/new-token") }
    let(:old_caskfile) { old_caskroom_path/".metadata/1.0/20240101000000/Casks/old-token.rb" }
    let(:new_caskfile) { new_caskroom_path/".metadata/1.0/20240101000000/Casks/new-token.rb" }
    let(:old_pin_path) { Pathname("/tmp/pinned_casks/old-token") }
    let(:new_pin_path) { Pathname("/tmp/pinned_casks/new-token") }
    let(:old_cask) do
      instance_double(
        Cask::Cask,
        token:              "old-token",
        caskroom_path:      old_caskroom_path,
        installed_caskfile: old_caskfile,
        pin_path:           old_pin_path,
        pinned_version:     "1.0",
      )
    end
    let(:new_cask) do
      instance_double(
        Cask::Cask,
        token:         "new-token",
        caskroom_path: new_caskroom_path,
        installed?:    true,
        pin_path:      new_pin_path,
      )
    end

    before do
      allow(old_pin_path).to receive(:symlink?).and_return(true)
      allow(FileUtils).to receive(:cp_r).with(old_caskroom_path, new_caskroom_path)
      allow(FileUtils).to receive(:mv).with(new_caskroom_path/old_caskfile.relative_path_from(old_caskroom_path),
                                            new_caskfile)
      allow(FileUtils).to receive(:rm_r).with(old_caskroom_path)
      allow(FileUtils).to receive(:ln_s).with(new_caskroom_path.basename, old_caskroom_path)
      allow(described_class).to receive(:replace_caskfile_token).with(new_caskfile, "old-token", "new-token")
    end

    it "moves a cask pin to the new token" do
      expect(old_cask).to receive(:unpin)
      expect(new_pin_path).to receive(:make_relative_symlink).with(new_caskroom_path/"1.0")

      described_class.new(old_cask, new_cask).migrate
    end

    it "prints relative cask pin targets in dry run" do
      expect do
        described_class.new(old_cask, new_cask).migrate(dry_run: true)
      end.to output(%r{ln -s ../Caskroom/new-token/1\.0 /tmp/pinned_casks/new-token}).to_stdout
    end

    it "does not remove the old cask pin when creating the new pin fails" do
      allow(new_pin_path).to receive(:make_relative_symlink).and_raise(RuntimeError, "failed")
      expect(old_cask).not_to receive(:unpin)

      expect do
        described_class.new(old_cask, new_cask).migrate
      end.to output(/Failed to migrate cask pin from old-token to new-token: failed/).to_stderr
    end
  end
end
