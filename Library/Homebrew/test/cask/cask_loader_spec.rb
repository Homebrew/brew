# typed: false
# frozen_string_literal: true

RSpec.describe Cask::CaskLoader, :cask do
  describe "::for" do
    let(:tap) { CoreCaskTap.instance }

    context "when a cask is renamed" do
      let(:old_token) { "version-newest" }
      let(:new_token) { "version-latest" }

      let(:api_casks) do
        [old_token, new_token].to_h do |token|
          hash = described_class.load(new_token).to_hash_with_variations
          json = JSON.pretty_generate(hash)
          cask_json = JSON.parse(json)

          [token, cask_json.except("token")]
        end
      end
      let(:cask_renames) do
        { old_token => new_token }
      end

      before do
        allow(Homebrew::API::Cask)
          .to receive(:all_casks)
          .and_return(api_casks)

        allow(tap).to receive(:cask_renames)
          .and_return(cask_renames)
      end

      context "when not using the API", :no_api do
        it "warns when using the short token" do
          expect do
            expect(described_class.for("version-newest")).to be_a Cask::CaskLoader::FromPathLoader
          end.to output(/version-newest was renamed to version-latest/).to_stderr
        end

        it "warns when using the full token" do
          expect do
            expect(described_class.for("homebrew/cask/version-newest")).to be_a Cask::CaskLoader::FromPathLoader
          end.to output(/version-newest was renamed to version-latest/).to_stderr
        end
      end

      context "when using the API" do
        it "warns when using the short token" do
          expect do
            expect(described_class.for("version-newest")).to be_a Cask::CaskLoader::FromAPILoader
          end.to output(/version-newest was renamed to version-latest/).to_stderr
        end

        it "warns when using the full token" do
          expect do
            expect(described_class.for("homebrew/cask/version-newest")).to be_a Cask::CaskLoader::FromAPILoader
          end.to output(/version-newest was renamed to version-latest/).to_stderr
        end
      end
    end

    context "when not using the API", :no_api do
      context "when a cask is migrated" do
        let(:token) { "local-caffeine" }

        let(:core_tap) { CoreTap.instance }
        let(:core_cask_tap) { CoreCaskTap.instance }

        let(:tap_migrations) do
          {
            token => new_tap.name,
          }
        end

        before do
          old_tap.path.mkpath
          new_tap.path.mkpath
          (old_tap.path/"tap_migrations.json").write tap_migrations.to_json
        end

        context "to a cask in an other tap" do
          # Can't use local-caffeine. It is a fixture in the :core_cask_tap and would take precedence over :new_tap.
          let(:token) { "some-cask" }

          let(:old_tap) { Tap.fetch("homebrew", "foo") }
          let(:new_tap) { Tap.fetch("homebrew", "bar") }

          let(:cask_file) { new_tap.cask_dir/"#{token}.rb" }

          before do
            new_tap.cask_dir.mkpath
            FileUtils.touch cask_file
          end

          # FIXME
          # It would be preferable not to print a warning when installing with the short token
          it "warns when loading the short token" do
            expect do
              described_class.for(token)
            end.to output(%r{Cask #{old_tap}/#{token} was renamed to #{new_tap}/#{token}\.}).to_stderr
          end

          it "does not warn when loading the full token in the new tap" do
            expect do
              described_class.for("#{new_tap}/#{token}")
            end.not_to output.to_stderr
          end

          it "warns when loading the full token in the old tap" do
            expect do
              described_class.for("#{old_tap}/#{token}")
            end.to output(%r{Cask #{old_tap}/#{token} was renamed to #{new_tap}/#{token}\.}).to_stderr
          end

          it "raises when the migrated tap is not installed" do
            FileUtils.rm_rf new_tap.path

            expect(new_tap).not_to receive(:ensure_installed!)

            expect { described_class.load("#{old_tap}/#{token}") }
              .to raise_error(Cask::TapCaskUnavailableError, /If you trust this tap/)
          end
        end

        context "to a formula in the default tap" do
          let(:old_tap) { core_cask_tap }
          let(:new_tap) { core_tap }

          let(:formula_file) { new_tap.formula_dir/"#{token}.rb" }

          before do
            new_tap.formula_dir.mkpath
            FileUtils.touch formula_file
          end

          it "warn only once" do
            expect do
              described_class.for(token)
            end.to output(
              a_string_including("Warning: Cask #{token} was renamed to #{new_tap}/#{token}.").once,
            ).to_stderr
          end
        end

        context "to the default tap" do
          let(:old_tap) { core_tap }
          let(:new_tap) { core_cask_tap }

          let(:cask_file) { new_tap.cask_dir/"#{token}.rb" }

          before do
            new_tap.cask_dir.mkpath
            FileUtils.touch cask_file
          end

          it "does not warn when loading the short token" do
            expect do
              described_class.for(token)
            end.not_to output.to_stderr
          end

          it "does not warn when loading the full token in the default tap" do
            expect do
              described_class.for("#{new_tap}/#{token}")
            end.not_to output.to_stderr
          end

          it "warns when loading the full token in the old tap" do
            expect do
              described_class.for("#{old_tap}/#{token}")
            end.to output(%r{Cask #{old_tap}/#{token} was renamed to #{token}\.}).to_stderr
          end

          # FIXME
          # context "when there is an infinite tap migration loop" do
          #   before do
          #     (new_tap.path/"tap_migrations.json").write({
          #       token => old_tap.name,
          #     }.to_json)
          #   end
          #
          #   it "stops recursing" do
          #     expect do
          #       described_class.for("#{new_tap}/#{token}")
          #     end.not_to output.to_stderr
          #   end
          # end
        end
      end
    end
  end

  describe "::load_prefer_installed" do
    let(:foo_tap) { Tap.fetch("user", "foo") }
    let(:bar_tap) { Tap.fetch("user", "bar") }

    let(:blank_tab) { instance_double(Cask::Tab, tap: nil) }
    let(:installed_tab) { instance_double(Cask::Tab, tap: bar_tap) }

    let(:cask_with_foo_tap) { instance_double(Cask::Cask, token: "test-cask", tap: foo_tap) }
    let(:cask_with_bar_tap) { instance_double(Cask::Cask, token: "test-cask", tap: bar_tap) }

    let(:load_args) { { config: nil, warn: true } }

    before do
      allow(described_class).to receive(:load).with("test-cask", load_args).and_return(cask_with_foo_tap)
      allow(described_class).to receive(:load).with("user/foo/test-cask", load_args).and_return(cask_with_foo_tap)
      allow(described_class).to receive(:load).with("user/bar/test-cask", load_args).and_return(cask_with_bar_tap)
    end

    it "returns the correct cask when no tap is specified and no tab exists" do
      allow_any_instance_of(Cask::Cask).to receive(:tab).and_return(blank_tab)
      expect(described_class).to receive(:load).with("test-cask", load_args)

      expect(described_class.load_prefer_installed("test-cask").tap).to eq(foo_tap)
    end

    it "returns the correct cask when no tap is specified but a tab exists" do
      allow_any_instance_of(Cask::Cask).to receive(:tab).and_return(installed_tab)
      expect(described_class).to receive(:load).with("user/bar/test-cask", load_args)

      expect(described_class.load_prefer_installed("test-cask").tap).to eq(bar_tap)
    end

    it "returns the correct cask when a tap is specified and no tab exists" do
      allow_any_instance_of(Cask::Cask).to receive(:tab).and_return(blank_tab)
      expect(described_class).to receive(:load).with("user/bar/test-cask", load_args)

      expect(described_class.load_prefer_installed("user/bar/test-cask").tap).to eq(bar_tap)
    end

    it "returns the correct cask when no tap is specified and a tab exists" do
      allow_any_instance_of(Cask::Cask).to receive(:tab).and_return(installed_tab)
      expect(described_class).to receive(:load).with("user/foo/test-cask", load_args)

      expect(described_class.load_prefer_installed("user/foo/test-cask").tap).to eq(foo_tap)
    end

    it "returns the correct cask when no tap is specified and the tab lists an tap that isn't installed" do
      allow_any_instance_of(Cask::Cask).to receive(:tab).and_return(installed_tab)
      expect(described_class).to receive(:load).with("user/bar/test-cask", load_args)
                                               .and_raise(Cask::CaskUnavailableError.new("test-cask", bar_tap))
      expect(described_class).to receive(:load).with("test-cask", load_args)

      expect(described_class.load_prefer_installed("test-cask").tap).to eq(foo_tap)
    end
  end

  describe "FromPathLoader" do
    describe "loading a cask with a removed DSL method" do
      let(:tmpdir) { mktmpdir }
      let(:cask_token) { "removed-method-cask" }
      let(:cask_file) { tmpdir/"#{cask_token}.rb" }
      let(:cask_content) do
        <<~RUBY
          cask "#{cask_token}" do
            version "1.0.0"
            sha256 "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

            url "https://example.com/app.dmg"
            appcast "https://example.com/appcast.xml"
            name "Removed Method Cask"
            homepage "https://example.com"

            app "App.app"
          end
        RUBY
      end

      before do
        tmpdir.mkpath
        cask_file.write(cask_content)
      end

      after do
        tmpdir.rmtree if tmpdir.exist?
      end

      it "raises CaskInvalidError" do
        loader = Cask::CaskLoader::FromPathLoader.new(cask_file)
        expect { loader.load(config: nil) }.to raise_error(Cask::CaskInvalidError)
      end

      it "does not set Homebrew.failed" do
        loader = Cask::CaskLoader::FromPathLoader.new(cask_file)
        expect { loader.load(config: nil) }.to raise_error(Cask::CaskInvalidError)
        expect(Homebrew).not_to be_failed
      end

      it "raises CaskUnreadableError when loaded from installed caskfile" do
        loader = Cask::CaskLoader::FromPathLoader.new(cask_file)
        loader.instance_variable_set(:@from_installed_caskfile, true)
        expect { loader.load(config: nil) }.to raise_error(Cask::CaskUnreadableError, /appcast/)
      end
    end

    describe "loading a cask JSON file with removed conflicts_with keys" do
      let(:tmpdir) { mktmpdir }
      let(:cask_token) { "removed-conflicts-key-cask" }
      let(:cask_file) { tmpdir/"#{cask_token}.json" }
      let(:cask_content) do
        <<~JSON
          {
            "token": "#{cask_token}",
            "full_token": "#{cask_token}",
            "tap": "homebrew/cask",
            "name": [],
            "desc": null,
            "homepage": "https://example.com",
            "url": "https://example.com/#{cask_token}.zip",
            "version": "1.0.0",
            "installed": null,
            "outdated": false,
            "sha256": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            "artifacts": [
              {
                "app": [
                  "App.app"
                ]
              }
            ],
            "caveats": null,
            "depends_on": {},
            "conflicts_with": {
              "formula": [
                "some-formula"
              ]
            },
            "container": null,
            "rename": [],
            "auto_updates": null,
            "tap_git_head": "abcdef1234567890abcdef1234567890abcdef12",
            "languages": [],
            "ruby_source_path": "Casks/#{cask_token}.rb",
            "ruby_source_checksum": {
              "sha256": "d3c19b564ee5a17f22191599ad795a6cc9c4758d0e1269f2d13207155b378dea"
            }
          }
        JSON
      end

      before do
        tmpdir.mkpath
        cask_file.write(cask_content)
      end

      after do
        tmpdir.rmtree if tmpdir.exist?
      end

      it "raises CaskInvalidError" do
        loader = Cask::CaskLoader::FromPathLoader.new(cask_file)
        expect { loader.load(config: nil) }.to raise_error(Cask::CaskInvalidError, /Unknown key: :formula/)
      end

      it "raises CaskUnreadableError when loaded from installed caskfile" do
        loader = Cask::CaskLoader::FromPathLoader.new(cask_file)
        loader.instance_variable_set(:@from_installed_caskfile, true)
        expect { loader.load(config: nil) }.to raise_error(Cask::CaskUnreadableError, /Unknown key: :formula/)
      end
    end
  end

  describe "FromPathLoader with symlinked taps" do
    let(:cask_token) { "testcask" }
    let(:tmpdir) { mktmpdir }
    let(:real_tap_path) { tmpdir / "real_tap" }
    let(:homebrew_prefix) { tmpdir / "homebrew" }
    let(:taps_dir) { homebrew_prefix / "Library" / "Taps" / "testuser" }
    let(:symlinked_tap_path) { taps_dir / "homebrew-testtap" }
    let(:cask_file_path) { symlinked_tap_path / "Casks" / "#{cask_token}.rb" }
    let(:cask_content) do
      <<~RUBY
        cask "#{cask_token}" do
          version "1.0.0"
          sha256 "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

          url "https://example.com/#{cask_token}-\#{version}.dmg"
          name "Test Cask"
          desc "A test cask for symlink testing"
          homepage "https://example.com"

          app "TestCask.app"
        end
      RUBY
    end

    after do
      tmpdir.rmtree if tmpdir.exist?
    end

    before do
      # Create real tap directory structure
      (real_tap_path / "Casks").mkpath
      (real_tap_path / "Casks" / "#{cask_token}.rb").write(cask_content)

      # Create homebrew prefix structure
      taps_dir.mkpath

      # Create symlink to the tap (this simulates what setup-homebrew does)
      symlinked_tap_path.make_symlink(real_tap_path)

      # Set HOMEBREW_LIBRARY to our test prefix for the security check
      stub_const("HOMEBREW_LIBRARY", homebrew_prefix / "Library")
      allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(true)
    end

    context "when HOMEBREW_FORBID_PACKAGES_FROM_PATHS is enabled" do
      it "allows loading casks from symlinked taps" do
        loader = Cask::CaskLoader::FromPathLoader.try_new(cask_file_path)
        expect(loader).not_to be_nil
        expect(loader).to be_a(Cask::CaskLoader::FromPathLoader)

        cask = loader.load(config: nil)
        expect(cask.token).to eq(cask_token)
        expect(cask.version).to eq(Version.new("1.0.0"))
      end
    end

    context "when HOMEBREW_FORBID_PACKAGES_FROM_PATHS is disabled" do
      before do
        allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(false)
      end

      it "allows loading casks from symlinked taps" do
        loader = Cask::CaskLoader::FromPathLoader.try_new(cask_file_path)
        expect(loader).not_to be_nil
        expect(loader).to be_a(Cask::CaskLoader::FromPathLoader)
      end
    end
  end
end
