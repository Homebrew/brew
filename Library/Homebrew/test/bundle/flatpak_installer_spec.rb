# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_installer"

RSpec.describe Homebrew::Bundle::FlatpakInstaller do
  context "when Flatpak is not installed", :needs_linux do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(false)
    end

    it "returns false without attempting installation" do
      expect(Homebrew::Bundle).not_to receive(:system)
      expect(described_class.preinstall!("org.gnome.Calculator")).to be(false)
      expect(described_class.install!("org.gnome.Calculator")).to be(true)
    end
  end

  context "when Flatpak is installed", :needs_linux do
    before do
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(true)
    end

    context "when package is installed" do
      before do
        allow(described_class).to receive(:installed_packages)
          .and_return([{ name: "org.gnome.Calculator", remote: "flathub" }])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("org.gnome.Calculator")).to be(false)
      end
    end

    context "when package is not installed" do
      before do
        allow(Homebrew::Bundle).to receive(:which_flatpak).and_return(Pathname.new("flatpak"))
        allow(described_class).to receive(:installed_packages).and_return([])
      end

      describe "Tier 1: no URL (flathub default)" do
        it "installs package from flathub" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "flathub", "org.gnome.Calculator",
                                  verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("org.gnome.Calculator")).to be(true)
          expect(described_class.install!("org.gnome.Calculator")).to be(true)
        end

        it "installs package from named remote" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "fedora", "org.gnome.Calculator",
                                  verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("org.gnome.Calculator", remote: "fedora")).to be(true)
          expect(described_class.install!("org.gnome.Calculator", remote: "fedora")).to be(true)
        end
      end

      describe "Tier 2: URL only (single-app remote)" do
        it "creates single-app remote with -origin suffix" do
          allow(described_class).to receive(:get_remote_url).and_return(nil)

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system", "--no-gpg-verify",
                                  "org.godotengine.Godot-origin", "https://dl.flathub.org/beta-repo/", verbose: false)
                            .and_return(true)
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "org.godotengine.Godot-origin",
                                  "org.godotengine.Godot", verbose: false)
                            .and_return(true)

          expect(described_class.preinstall!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
            .to be(true)
          expect(described_class.install!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
            .to be(true)
        end

        it "replaces single-app remote when URL changes" do
          allow(described_class).to receive(:get_remote_url)
            .with(anything, "org.godotengine.Godot-origin")
            .and_return("https://old.url/repo/")

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "remote-delete", "--system", "--force",
                                  "org.godotengine.Godot-origin", verbose: false)
                            .and_return(true)
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system", "--no-gpg-verify",
                                  "org.godotengine.Godot-origin", "https://dl.flathub.org/beta-repo/", verbose: false)
                            .and_return(true)
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "org.godotengine.Godot-origin",
                                  "org.godotengine.Godot", verbose: false)
                            .and_return(true)

          expect(described_class.install!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
            .to be(true)
        end

        it "installs from .flatpakref directly" do
          allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                               .and_return("org.example.App\texample-origin\n")

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system",
                                  "https://example.com/app.flatpakref", verbose: false)
                            .and_return(true)

          expect(described_class.install!("org.example.App", remote: "https://example.com/app.flatpakref"))
            .to be(true)
        end
      end

      describe "Tier 3: URL + name (shared remote)" do
        it "creates named shared remote" do
          allow(described_class).to receive(:get_remote_url).and_return(nil)

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system", "--no-gpg-verify",
                                  "flathub-beta", "https://dl.flathub.org/beta-repo/", verbose: false)
                            .and_return(true)
          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "flathub-beta",
                                  "org.godotengine.Godot", verbose: false)
                            .and_return(true)

          expect(described_class.install!("org.godotengine.Godot",
                                          remote: "flathub-beta",
                                          url:    "https://dl.flathub.org/beta-repo/"))
            .to be(true)
        end

        it "warns but uses existing remote with different URL" do
          allow(described_class).to receive(:get_remote_url)
            .with(anything, "flathub-beta")
            .and_return("https://different.url/repo/")

          # Should NOT try to add remote (uses existing)
          expect(Homebrew::Bundle).not_to receive(:system)
            .with("flatpak", "remote-add", any_args)
          # Should NOT try to delete remote (user explicitly named it)
          expect(Homebrew::Bundle).not_to receive(:system)
            .with("flatpak", "remote-delete", any_args)

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "flathub-beta",
                                  "org.godotengine.Godot", verbose: false)
                            .and_return(true)

          expect(described_class.install!("org.godotengine.Godot",
                                          remote: "flathub-beta",
                                          url:    "https://dl.flathub.org/beta-repo/"))
            .to be(true)
        end

        it "reuses existing shared remote when URL matches" do
          allow(described_class).to receive(:get_remote_url)
            .with(anything, "flathub-beta")
            .and_return("https://dl.flathub.org/beta-repo/")

          # Should NOT try to add remote (already exists with same URL)
          expect(Homebrew::Bundle).not_to receive(:system)
            .with("flatpak", "remote-add", any_args)

          expect(Homebrew::Bundle).to \
            receive(:system).with("flatpak", "install", "-y", "--system", "flathub-beta",
                                  "org.godotengine.Godot", verbose: false)
                            .and_return(true)

          expect(described_class.install!("org.godotengine.Godot",
                                          remote: "flathub-beta",
                                          url:    "https://dl.flathub.org/beta-repo/"))
            .to be(true)
        end
      end
    end
  end

  describe ".generate_single_app_remote_name" do
    it "generates name with -origin suffix" do
      expect(described_class.generate_single_app_remote_name("org.godotengine.Godot"))
        .to eq("org.godotengine.Godot-origin")
    end

    it "handles various app ID formats" do
      expect(described_class.generate_single_app_remote_name("com.example.App"))
        .to eq("com.example.App-origin")
    end
  end
end
