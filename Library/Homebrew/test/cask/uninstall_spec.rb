# frozen_string_literal: true

require "cask/uninstall"

RSpec.describe Cask::Uninstall, :cask do
  describe ".uninstall_casks" do
    it "displays the uninstallation progress" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      Cask::Installer.new(caffeine).install

      output = Regexp.new <<~EOS
        ==> Uninstalling Cask local-caffeine
        ==> Backing App 'Caffeine.app' up to '.*Caffeine.app'
        ==> Removing App '.*Caffeine.app'
        ==> Purging files for version 1.2.3 of Cask local-caffeine
      EOS

      expect do
        described_class.uninstall_casks(caffeine)
      end.to output(output).to_stdout
    end

    it "shows an error when a Cask is provided that's not installed" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      expect { described_class.uninstall_casks(caffeine) }
        .to raise_error(Cask::CaskNotInstalledError, /is not installed/)
    end

    it "tries anyway on a non-present Cask when --force is given" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      expect do
        described_class.uninstall_casks(caffeine, force: true)
      end.not_to raise_error
    end

    it "can uninstall and unlink multiple Casks at once" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))

      Cask::Installer.new(caffeine).install
      Cask::Installer.new(transmission).install

      expect(caffeine).to be_installed
      expect(transmission).to be_installed

      described_class.uninstall_casks(caffeine, transmission)

      expect(caffeine).not_to be_installed
      expect(caffeine.config.appdir.join("Transmission.app")).not_to exist
      expect(transmission).not_to be_installed
      expect(transmission.config.appdir.join("Caffeine.app")).not_to exist
    end

    it "can uninstall Casks when the uninstall script is missing, but only when using `--force`" do
      cask = Cask::CaskLoader.load(cask_path("with-uninstall-script-app"))

      Cask::Installer.new(cask).install

      expect(cask).to be_installed

      FileUtils.rm_r(cask.config.appdir.join("MyFancyApp.app"))

      expect { described_class.uninstall_casks(cask) }
        .to raise_error(Cask::CaskError, /uninstall script .* does not exist/)

      expect(cask).to be_installed

      expect do
        described_class.uninstall_casks(cask, force: true)
      end.not_to raise_error

      expect(cask).not_to be_installed
    end

    describe "when multiple versions of a cask are installed" do
      let(:token) { "versioned-cask" }
      let(:first_installed_version) { "1.2.3" }
      let(:last_installed_version) { "4.5.6" }
      let(:timestamped_versions) do
        [
          [first_installed_version, "123000"],
          [last_installed_version,  "456000"],
        ]
      end
      let(:caskroom_path) { Cask::Caskroom.path.join(token).tap(&:mkpath) }

      before do
        timestamped_versions.each do |timestamped_version|
          caskroom_path.join(".metadata", *timestamped_version, "Casks").tap(&:mkpath)
                       .join("#{token}.rb").open("w") do |caskfile|
                         caskfile.puts <<~RUBY
                           cask '#{token}' do
                             version '#{timestamped_version[0]}'
                           end
                         RUBY
                       end
          caskroom_path.join(timestamped_version[0]).mkpath
        end
      end

      it "uninstalls one version at a time" do
        described_class.uninstall_casks(Cask::Cask.new("versioned-cask"))

        expect(caskroom_path.join(first_installed_version)).to exist
        expect(caskroom_path.join(last_installed_version)).not_to exist
        expect(caskroom_path).to exist

        described_class.uninstall_casks(Cask::Cask.new("versioned-cask"))

        expect(caskroom_path.join(first_installed_version)).not_to exist
        expect(caskroom_path).not_to exist
      end
    end

    context "when Casks in Taps have been renamed or removed" do
      let(:app) { Cask::Config.new.appdir.join("ive-been-renamed.app") }
      let(:caskroom_path) { Cask::Caskroom.path.join("ive-been-renamed").tap(&:mkpath) }
      let(:saved_caskfile) do
        caskroom_path.join(".metadata", "latest", "timestamp", "Casks").join("ive-been-renamed.rb")
      end

      before do
        app.tap(&:mkpath)
           .join("Contents")
           .tap(&:mkpath)
           .join("Info.plist")
           .tap { |file| FileUtils.touch(file) }

        caskroom_path.mkpath

        saved_caskfile.dirname.mkpath

        File.write saved_caskfile, <<~RUBY
          cask 'ive-been-renamed' do
            version :latest

            app 'ive-been-renamed.app'
          end
        RUBY
      end

      it "can still uninstall them" do
        described_class.uninstall_casks(Cask::Cask.new("ive-been-renamed"))

        expect(app).not_to exist
        expect(caskroom_path).not_to exist
      end
    end
  end

  describe ".check_dependent_casks" do
    it "shows error message when trying to uninstall a cask with dependents" do
      depends_on_cask = Cask::CaskLoader.load(cask_path("with-depends-on-cask"))
      local_transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))

      allow(Cask::Caskroom).to receive(:casks).and_return([depends_on_cask, local_transmission])

      output = <<~EOS
        Error: Refusing to uninstall local-transmission-zip
        because it is required by with-depends-on-cask, which is currently installed.
        You can override this and force removal with:
          brew uninstall --ignore-dependencies local-transmission-zip
      EOS

      expect do
        described_class.check_dependent_casks(local_transmission, named_args: ["local-transmission-zip"])
      end.to output(output).to_stderr
    end

    it "shows error message when trying to uninstall a cask with multiple dependents" do
      depends_on_cask = Cask::CaskLoader.load(cask_path("with-depends-on-cask"))
      depends_on_cask_multiple = Cask::CaskLoader.load(cask_path("with-depends-on-cask-multiple"))
      local_transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))

      allow(Cask::Caskroom).to receive(:casks).and_return([
        depends_on_cask,
        depends_on_cask_multiple,
        local_transmission,
      ])

      output = <<~EOS
        Error: Refusing to uninstall local-transmission-zip
        because it is required by with-depends-on-cask and with-depends-on-cask-multiple, which are currently installed.
        You can override this and force removal with:
          brew uninstall --ignore-dependencies local-transmission-zip
      EOS

      expect do
        described_class.check_dependent_casks(local_transmission, named_args: ["local-transmission-zip"])
      end.to output(output).to_stderr
    end

    it "shows error message when trying to uninstall multiple casks with dependents" do
      depends_on_cask = Cask::CaskLoader.load(cask_path("with-depends-on-cask"))
      depends_on_everything = Cask::CaskLoader.load(cask_path("with-depends-on-everything"))
      local_caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      local_transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))
      named_args = %w[local-transmission-zip local-caffeine]

      allow(Cask::Caskroom).to receive(:casks).and_return([
        depends_on_cask,
        depends_on_everything,
        local_caffeine,
        local_transmission,
      ])

      output = <<~EOS
        Error: Refusing to uninstall local-transmission-zip and local-caffeine
        because they are required by with-depends-on-cask and with-depends-on-everything, which are currently installed.
        You can override this and force removal with:
          brew uninstall --ignore-dependencies local-transmission-zip local-caffeine
      EOS

      expect do
        described_class.check_dependent_casks(local_transmission, local_caffeine, named_args:)
      end.to output(output).to_stderr
    end

    it "does not output an error if no dependents found" do
      depends_on_cask = Cask::CaskLoader.load(cask_path("with-depends-on-cask"))
      local_transmission = Cask::CaskLoader.load(cask_path("local-transmission"))

      allow(Cask::Caskroom).to receive(:casks).and_return([depends_on_cask, local_transmission])

      expect do
        described_class.check_dependent_casks(depends_on_cask, named_args: ["with-depends-on-cask"])
      end.not_to output.to_stderr
    end

    it "lists other named args when showing the error message" do
      depends_on_cask = Cask::CaskLoader.load(cask_path("with-depends-on-cask"))
      local_transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))
      named_args = %w[local-transmission-zip foo bar baz qux]

      allow(Cask::Caskroom).to receive(:casks).and_return([depends_on_cask, local_transmission])

      output = <<~EOS
        Error: Refusing to uninstall local-transmission-zip
        because it is required by with-depends-on-cask, which is currently installed.
        You can override this and force removal with:
          brew uninstall --ignore-dependencies local-transmission-zip foo bar baz qux
      EOS

      expect do
        described_class.check_dependent_casks(local_transmission, named_args:)
      end.to output(output).to_stderr
    end
  end
end
