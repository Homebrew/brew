# typed: strict
# frozen_string_literal: true

require "cask/installer"
require "cask/reinstall"

RSpec.describe Cask::Reinstall, :cask do
  it "displays the reinstallation progress" do
    caffeine = Cask::CaskLoader.from_path(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Uninstalling Cask local-caffeine
      ==> Backing up App 'Caffeine.app' to '.*Caffeine.app'
      ==> Removing App '.*Caffeine.app'
      ==> Purging files for version 1.2.3 of Cask local-caffeine
      ==> Installing Cask local-caffeine
      ==> Moving App 'Caffeine.app' to '.*Caffeine.app'
      .*local-caffeine was successfully installed!
    EOS

    expect do
      described_class.reinstall_casks(Cask::CaskLoader.load("local-caffeine"))
    end.to output(output).to_stdout.and output(/==> Fetching downloads for: local-caffeine/).to_stderr
  end

  it "displays the reinstallation progress with zapping" do
    caffeine = Cask::CaskLoader.from_path(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Zapping Cask local-caffeine
      ==> Backing up App 'Caffeine.app' to '.*Caffeine.app'
      ==> Removing App '.*Caffeine.app'
      ==> Trashing files:
      .*org.example.caffeine.plist
      ==> Removing all staged versions of Cask 'local-caffeine'
      ==> Installing Cask local-caffeine
      ==> Moving App 'Caffeine.app' to '.*Caffeine.app'
      .*local-caffeine was successfully installed!
    EOS

    expect do
      described_class.reinstall_casks(Cask::CaskLoader.load("local-caffeine"), zap: true)
    end.to output(output).to_stdout.and output(/==> Fetching downloads for: local-caffeine/).to_stderr
  end

  it "allows reinstalling a Cask" do
    Cask::Installer.new(Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))).install

    expect(Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))).to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission-zip"))
    expect(Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))).to be_installed
  end

  it "preserves Finder tags on reinstalled apps", :needs_macos do
    caffeine = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
    Cask::Installer.new(caffeine).install
    app = (caffeine.config.appdir/"Caffeine.app").to_s
    red_work_tag = "Work\n6"
    MacOS::FFI.set_xattr(app, MacOS::FFI::FINDER_TAGS_XATTR, red_work_tag)

    described_class.reinstall_casks(Cask::CaskLoader.load("local-caffeine"))

    expect(MacOS::FFI.get_xattr(app, MacOS::FFI::FINDER_TAGS_XATTR)).to eq(red_work_tag)
  end

  context "when adopting an app that the previous cask did not own" do
    sig { returns([Cask::Cask, Pathname]) }
    def cask_with_existing_app
      cask = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
      Cask::Installer.new(cask).install
      target_path = cask.config.appdir/"Other Caffeine.app"
      FileUtils.cp_r cask.config.appdir/"Caffeine.app", target_path
      replacement_cask = Cask::CaskLoader.from_content(
        cask_path("local-caffeine").read.sub('app "Caffeine.app"',
                                             'app "Caffeine.app", target: "Other Caffeine.app"'),
      )

      [replacement_cask, target_path]
    end

    it "preserves the existing app when reinstalling successfully" do
      replacement_cask, target_path = cask_with_existing_app
      original_inode = target_path.stat.ino

      expect(described_class.reinstall_casks(replacement_cask, adopt: true)).to eq([replacement_cask])
      expect(target_path.stat.ino).to eq(original_inode)
    end

    test_each([false, true].product([false, true])) do |supplied_installers, existing_app|
      it "rolls back a failed reinstall (supplied: #{supplied_installers}, existing app: #{existing_app})" do
        replacement_cask, target_path = cask_with_existing_app
        FileUtils.rm_r target_path unless existing_app
        original_stat = target_path.stat if existing_app
        failing_cask = Cask::CaskLoader.from_content(
          replacement_cask.source.to_s.sub('app "Caffeine.app"', "binary \"missing-binary\"\n  app \"Caffeine.app\""),
        )
        download_queue = Homebrew::DownloadQueue.default
        if supplied_installers
          cask_installers = [Cask::Installer.new(failing_cask, adopt: true, reinstall: true,
                                                            download_queue:, defer_fetch: true)]
        end

        expect do
          described_class.reinstall_casks(failing_cask, adopt: true, binaries: true,
                                                       download_queue:, cask_installers:)
        end.to output(/missing-binary.*not there/).to_stderr

        if original_stat
          expect(target_path.stat.ino).to eq(original_stat.ino)
        else
          expect(target_path).not_to exist
        end
      end
    end
  end

  it "continues reinstalling remaining casks when one raises" do
    cask1 = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
    cask2 = Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))

    Cask::Installer.new(cask1).install
    Cask::Installer.new(cask2).install

    failing_installer = instance_double(Cask::Installer, cask: cask1)
    allow(failing_installer).to receive(:prelude)
    allow(failing_installer).to receive(:enqueue_downloads)
    allow(failing_installer).to receive(:enqueue_dependency_downloads)
    allow(failing_installer).to receive(:install).and_raise(Cask::CaskError.new("reinstall failed"))

    successful_installer = instance_double(Cask::Installer, cask: cask2)
    allow(successful_installer).to receive(:prelude)
    allow(successful_installer).to receive(:enqueue_downloads)
    allow(successful_installer).to receive(:enqueue_dependency_downloads)

    allow(Cask::Installer).to receive(:new).and_return(failing_installer, successful_installer)

    expect(successful_installer).to receive(:install)
    expect { described_class.reinstall_casks(cask1, cask2) }
      .to output(/local-caffeine: reinstall failed/).to_stderr
  end

  it "returns reinstalled casks without a caveat mode option" do
    cask = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
    installer = instance_double(Cask::Installer, cask:, install: nil)

    expect(Cask::Installer).to receive(:new) do |new_cask, **options|
      expect(new_cask).to eq(cask)
      expect(options).not_to have_key(:defer_caveats)
      installer
    end

    expect(described_class.reinstall_casks(cask, skip_prefetch: true)).to eq([cask])
  end

  it "returns the casks from supplied installers" do
    requested_cask = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
    reinstalled_cask = Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))
    installer = Cask::Installer.allocate
    allow(installer).to receive_messages(cask: reinstalled_cask, install: nil)

    expect(described_class.reinstall_casks(
             requested_cask,
             skip_prefetch:   true,
             cask_installers: [installer],
           )).to eq([reinstalled_cask])
  end

  it "reinstalls casks after an earlier failure in the same run" do
    cask = Cask::CaskLoader.from_path(cask_path("local-caffeine"))
    installer = instance_double(Cask::Installer, cask:, prelude: nil, enqueue_downloads: nil,
                                                 enqueue_dependency_downloads: nil)
    allow(Cask::Installer).to receive(:new).and_return(installer)
    # A failure earlier in the run (e.g. a formula in the same `brew reinstall`)
    # must not stop the casks that are ready from being reinstalled.
    Homebrew.failed = true

    expect(installer).to receive(:install)

    described_class.reinstall_casks(cask)
  end

  it "allows reinstalling a non installed Cask" do
    expect(Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))).not_to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission-zip"))
    expect(Cask::CaskLoader.from_path(cask_path("local-transmission-zip"))).to be_installed
  end
end
