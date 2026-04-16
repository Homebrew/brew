# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/flatpak"

RSpec.describe Homebrew::Bundle::Flatpak do
  describe "checking" do
    subject(:checker) { described_class.new }

    before do
      allow(described_class).to receive(:package_installed?).and_return(false)
    end

    describe "#installed_and_up_to_date?", :needs_linux do
      it "returns false when package is not installed" do
        expect(checker.installed_and_up_to_date?("org.gnome.Calculator")).to be(false)
      end

      it "returns true when package is installed" do
        allow(described_class).to receive(:package_installed?).and_return(true)
        expect(checker.installed_and_up_to_date?("org.gnome.Calculator")).to be(true)
      end

      describe "3-tier remote handling" do
        it "checks Tier 1 package with default remote (flathub)" do
          allow(described_class).to receive(:package_installed?)
            .with("org.gnome.Calculator", remote: "flathub")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.gnome.Calculator", options: {} },
          )
          expect(result).to be(true)
        end

        it "checks Tier 1 package with named remote" do
          allow(described_class).to receive(:package_installed?)
            .with("org.gnome.Calculator", remote: "fedora")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.gnome.Calculator", options: { remote: "fedora" } },
          )
          expect(result).to be(true)
        end

        it "checks Tier 2 package with URL remote (resolves to single-app remote)" do
          allow(described_class).to receive(:package_installed?)
            .with("org.godotengine.Godot", remote: "org.godotengine.Godot-origin")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.godotengine.Godot", options: { remote: "https://dl.flathub.org/beta-repo/" } },
          )
          expect(result).to be(true)
        end

        it "checks Tier 2 package with .flatpakref by name only" do
          allow(described_class).to receive(:package_installed?)
            .with("org.example.App")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.example.App", options: { remote: "https://example.com/app.flatpakref" } },
          )
          expect(result).to be(true)
        end

        it "checks Tier 3 package with URL and remote name" do
          allow(described_class).to receive(:package_installed?)
            .with("org.godotengine.Godot", remote: "flathub-beta")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name:    "org.godotengine.Godot",
              options: { remote: "flathub-beta", url: "https://dl.flathub.org/beta-repo/" } },
          )
          expect(result).to be(true)
        end
      end
    end

    describe "#failure_reason", :needs_linux do
      it "returns the correct failure message" do
        expect(checker.failure_reason("org.gnome.Calculator", no_upgrade: false))
          .to eq("Flatpak org.gnome.Calculator needs to be installed.")
      end

      it "returns the correct failure message for hash package" do
        expect(checker.failure_reason({ name: "org.gnome.Calculator", options: {} }, no_upgrade: false))
          .to eq("Flatpak org.gnome.Calculator needs to be installed.")
      end
    end

    context "when on macOS", :needs_macos do
      it "flatpak is not available" do
        expect(described_class.package_manager_installed?).to be(false)
      end
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when flatpak is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns an empty list and dumps an empty string" do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when flatpak is installed", :needs_linux do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("flatpak"))
      end

      it "returns remote URLs" do
        allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                             .and_return("flathub\thttps://dl.flathub.org/repo/\nfedora\thttps://registry.fedoraproject.org/\n")
        expect(dumper.remote_urls).to eql({
          "flathub" => "https://dl.flathub.org/repo/",
          "fedora"  => "https://registry.fedoraproject.org/",
        })
      end

      it "returns package list with remotes and URLs" do
        allow(described_class).to receive(:`)
          .with("flatpak list --app --columns=application,origin 2>/dev/null")
          .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
        allow(described_class).to receive(:`)
          .with("flatpak remote-list --system --columns=name,url 2>/dev/null")
          .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages_with_remotes).to eql([
          { name: "com.spotify.Client", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
          { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        ])
      end

      it "returns package names only" do
        allow(described_class).to receive(:`)
          .with("flatpak list --app --columns=application,origin 2>/dev/null")
          .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
        allow(described_class).to receive(:`)
          .with("flatpak remote-list --system --columns=name,url 2>/dev/null")
          .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages).to eql(["com.spotify.Client", "org.gnome.Calculator"])
      end

      describe "3-tier dump format" do
        it "dumps Tier 1 packages without remote (flathub default)" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
            { name: "com.spotify.Client", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
          ])
          expect(dumper.dump).to eql("flatpak \"org.gnome.Calculator\"\nflatpak \"com.spotify.Client\"")
        end

        it "dumps Tier 2 packages with URL only (single-app remote)" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.godotengine.Godot", remote: "org.godotengine.Godot-origin",
              remote_url: "https://dl.flathub.org/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"org.godotengine.Godot\", remote: \"https://dl.flathub.org/beta-repo/\"",
          )
        end

        it "dumps Tier 2 packages with remote name if URL not available" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.example.App", remote: "org.example.App-origin", remote_url: nil },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"org.example.App\", remote: \"org.example.App-origin\"",
          )
        end

        it "dumps Tier 3 packages with remote name and URL (shared remote)" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.godotengine.Godot", remote: "flathub-beta",
              remote_url: "https://dl.flathub.org/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"org.godotengine.Godot\", remote: \"flathub-beta\", url: \"https://dl.flathub.org/beta-repo/\"",
          )
        end

        it "dumps named remote without URL when URL is not available" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "com.custom.App", remote: "custom-repo", remote_url: nil },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"com.custom.App\", remote: \"custom-repo\"",
          )
        end

        it "dumps mixed packages correctly" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "com.spotify.Client", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
            { name: "org.godotengine.Godot", remote: "org.godotengine.Godot-origin",
              remote_url: "https://dl.flathub.org/beta-repo/" },
            { name: "io.github.dvlv.boxbuddyrs", remote: "flathub-beta",
              remote_url: "https://dl.flathub.org/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"com.spotify.Client\"\n" \
            "flatpak \"org.godotengine.Godot\", remote: \"https://dl.flathub.org/beta-repo/\"\n" \
            "flatpak \"io.github.dvlv.boxbuddyrs\", remote: \"flathub-beta\", url: \"https://dl.flathub.org/beta-repo/\"",
          )
        end
      end

      it "handles packages without origin" do
        allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                             .and_return("org.gnome.Calculator\n")
        allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                             .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages_with_remotes).to eql([
          { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        ])
      end
    end
  end

  describe "installing" do
    context "when Flatpak is not installed", :needs_linux do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns false without attempting installation" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("org.gnome.Calculator")).to be(false)
        expect(described_class.install!("org.gnome.Calculator")).to be(true)
      end
    end

    context "when Flatpak is installed", :needs_linux do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("flatpak"))
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
              receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system",
                                    "--no-gpg-verify", "org.godotengine.Godot-origin",
                                    "https://dl.flathub.org/beta-repo/", verbose: false)
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
              receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system",
                                    "--no-gpg-verify", "org.godotengine.Godot-origin",
                                    "https://dl.flathub.org/beta-repo/", verbose: false)
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
end
