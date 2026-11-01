# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/extensions/flatpak"

RSpec.describe Homebrew::Bundle::Flatpak do
  let(:inventory_records) { ["Example.App"] }
  let(:inventory_output) { "Example.App\tflathub\n" }

  describe "checked remote inventory" do
    let(:inventory_output) { "flathub\thttps://example.com/repo/\n" }
    let(:inventory_records) { { "flathub" => "https://example.com/repo/" } }

    it_behaves_like "a checked inventory", :remote_urls, empty_inventory: {}
  end

  describe "remote row line endings" do
    before do
      described_class.reset!
    end

    after do
      described_class.reset!
    end

    it "reads a remote URL from an LF row before the final row" do
      allow(described_class).to receive(:command_output)
        .with("flatpak", args: ["remote-list", "--system", "--columns=name,url"])
        .and_return("flathub\thttps://example.com/repo/\nother\thttps://example.com/other/\n")

      expect(described_class.get_remote_url("flatpak", "flathub")).to eq("https://example.com/repo/")
    end

    it "reads an installed origin from an LF row before the final row" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      allow(described_class).to receive(:command_output)
        .with("flatpak", args: ["list", "--app", "--columns=application,origin"])
        .and_return("Example.App\texample-origin\nOther.App\tother-origin\n")

      described_class.install_flatpakref!("flatpak", "Example.App", "https://example.com/app.flatpakref",
                                          verbose: false)

      expect(described_class.installed_packages)
        .to eq([{ name: "Example.App", remote: "example-origin", remote_url: nil }])
    end
  end

  describe "remote discovery failures" do
    let(:flatpak) { mktmpdir/"flatpak" }
    let(:successful_inventory_script) do
      <<~SH
        #!/bin/sh
        case "$1" in
          list) printf 'Example.App\\tflathub\\n' ;;
          remote-list) printf 'flathub\\thttps://example.com/repo/\\n' ;;
          *) exit 2 ;;
        esac
      SH
    end

    before do
      described_class.reset!
      flatpak.write <<~SH
        #!/bin/sh
        if [ "$1" = list ]; then printf 'Example.App\\tflathub\\n'; exit 0; fi
        printf '%s\\n' 'remote unavailable' >&2
        exit 2
      SH
      flatpak.chmod 0755
      allow(described_class).to receive(:package_manager_executable).and_return(flatpak)
    end

    after do
      described_class.reset!
    end

    it "rejects remote failure after a successful package listing" do
      expect { described_class.packages }.to raise_error(ErrorDuringExecution, /remote unavailable/)
    end

    it "retries remote discovery without reset" do
      expect { described_class.packages }.to raise_error(ErrorDuringExecution)
      flatpak.write successful_inventory_script
      expect(described_class.packages_with_remotes)
        .to eq([{ name: "Example.App", remote: "flathub", remote_url: "https://example.com/repo/" }])
    end

    it "reports refresh failure after installation without reinstalling" do
      flatpak.write successful_inventory_script
      described_class.packages
      expect(Homebrew::Bundle).to receive(:system).once.and_return(true)
      flatpak.write "#!/bin/sh\nexit 2\n"
      expect do
        described_class.install_flatpakref!(flatpak.to_s, "Example.App", "https://example.com/app.flatpakref",
                                            verbose: false)
      end.to raise_error(ErrorDuringExecution)
      flatpak.write "#!/bin/sh\nexit 0\n"
      expect(described_class.packages).to eq([])
    end
  end

  describe "checked inventory" do
    before do
      allow(described_class).to receive(:remote_urls).and_return({})
    end

    it_behaves_like "a checked package inventory"

    context "with installed records" do
      let(:inventory_records) { [{ name: "Example.App", remote: "flathub", remote_url: nil }] }

      it_behaves_like "a checked inventory", :installed_packages
    end
  end

  describe "cleanup" do
    test_each([false, nil]) do |result|
      it "continues after #{result.inspect} with the resolved executable and unchanged environment" do
        Homebrew.failed = false
        ENV["PATH"] = "/usr/bin:/bin"
        allow(described_class).to receive(:package_manager_executable)
          .and_return(Pathname("/example/bin/flatpak"))
        expect(Kernel).to receive(:system)
          .with("/example/bin/flatpak", "uninstall", "-y", "--system", "org.example.App").ordered do
          expect(ENV.fetch("PATH")).to eq("/usr/bin:/bin")
          result
        end
        expect(Kernel).to receive(:system)
          .with("/example/bin/flatpak", "uninstall", "-y", "--system", "org.example.Second")
          .ordered.and_return(true)

        expect do
          described_class.cleanup!(%w[org.example.App org.example.Second])
        end.to(
          change(Homebrew, :failed?).from(false).to(true)
            .and(output(
              a_string_including("Failed to uninstall Flatpak packages: org.example.App"),
            ).to_stderr)
            .and(output("Uninstalled 1 flatpak\n").to_stdout),
        )
      end
    end
  end

  describe "checking" do
    subject(:checker) { described_class.new }

    before do
      allow(described_class).to receive(:package_installed?).and_return(false)
    end

    describe "#installed_and_up_to_date?", :needs_linux do
      it "returns false when package is not installed" do
        expect(checker.installed_and_up_to_date?("org.example.App")).to be(false)
      end

      it "returns true when package is installed" do
        allow(described_class).to receive(:package_installed?).and_return(true)
        expect(checker.installed_and_up_to_date?("org.example.App")).to be(true)
      end

      describe "3-tier remote handling" do
        it "checks Tier 1 package with default remote (flathub)" do
          allow(described_class).to receive(:package_installed?)
            .with("org.example.App", remote: "flathub")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.example.App", options: {} },
          )
          expect(result).to be(true)
        end

        it "checks Tier 1 package with named remote" do
          allow(described_class).to receive(:package_installed?)
            .with("org.example.App", remote: "example-remote")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.example.App", options: { remote: "example-remote" } },
          )
          expect(result).to be(true)
        end

        it "checks Tier 2 package with URL remote (resolves to single-app remote)" do
          allow(described_class).to receive(:package_installed?)
            .with("org.example.SourceApp", remote: "org.example.SourceApp-origin")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name: "org.example.SourceApp", options: { remote: "https://example.com/beta-repo/" } },
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
            .with("org.example.SourceApp", remote: "example-beta")
            .and_return(true)

          result = checker.installed_and_up_to_date?(
            { name:    "org.example.SourceApp",
              options: { remote: "example-beta", url: "https://example.com/beta-repo/" } },
          )
          expect(result).to be(true)
        end
      end
    end

    describe "#failure_reason", :needs_linux do
      it "returns the correct failure message" do
        expect(checker.failure_reason("org.example.App", no_upgrade: false))
          .to eq("Flatpak org.example.App needs to be installed.")
      end

      it "returns the correct failure message for hash package" do
        expect(checker.failure_reason({ name: "org.example.App", options: {} }, no_upgrade: false))
          .to eq("Flatpak org.example.App needs to be installed.")
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
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["remote-list", "--system", "--columns=name,url"])
          .and_return("flathub\thttps://dl.flathub.org/repo/\nexample-remote\thttps://example.com/other-repo/\n")
        expect(dumper.remote_urls).to eql({
          "flathub"        => "https://dl.flathub.org/repo/",
          "example-remote" => "https://example.com/other-repo/",
        })
      end

      it "returns package list with remotes and URLs" do
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["list", "--app", "--columns=application,origin"])
          .and_return("org.example.App\tflathub\ncom.example.OtherApp\tflathub\n")
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["remote-list", "--system", "--columns=name,url"])
          .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages_with_remotes).to eql([
          { name: "com.example.OtherApp", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
          { name: "org.example.App", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        ])
      end

      it "returns package names only" do
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["list", "--app", "--columns=application,origin"])
          .and_return("org.example.App\tflathub\ncom.example.OtherApp\tflathub\n")
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["remote-list", "--system", "--columns=name,url"])
          .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages).to eql(["com.example.OtherApp", "org.example.App"])
      end

      describe "3-tier dump format" do
        it "dumps Tier 1 packages without remote (flathub default)" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.example.App", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
            { name: "com.example.OtherApp", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
          ])
          expect(dumper.dump).to eql("flatpak \"org.example.App\"\nflatpak \"com.example.OtherApp\"")
        end

        it "dumps Tier 2 packages with URL only (single-app remote)" do
          allow(dumper).to receive(:packages_with_remotes).and_return([
            { name: "org.example.SourceApp", remote: "org.example.SourceApp-origin",
              remote_url: "https://example.com/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"org.example.SourceApp\", remote: \"https://example.com/beta-repo/\"",
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
            { name: "org.example.SourceApp", remote: "example-beta",
              remote_url: "https://example.com/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"org.example.SourceApp\", remote: \"example-beta\", url: \"https://example.com/beta-repo/\"",
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
            { name: "com.example.OtherApp", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
            { name: "org.example.SourceApp", remote: "org.example.SourceApp-origin",
              remote_url: "https://example.com/beta-repo/" },
            { name: "io.example.ThirdApp", remote: "example-beta",
              remote_url: "https://example.com/beta-repo/" },
          ])
          expect(dumper.dump).to eql(
            "flatpak \"com.example.OtherApp\"\n" \
            "flatpak \"org.example.SourceApp\", remote: \"https://example.com/beta-repo/\"\n" \
            "flatpak \"io.example.ThirdApp\", remote: \"example-beta\", url: \"https://example.com/beta-repo/\"",
          )
        end
      end

      it "handles packages without origin" do
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["list", "--app", "--columns=application,origin"])
          .and_return("org.example.App\n")
        allow(described_class).to receive(:command_output)
          .with(Pathname("flatpak"), args: ["remote-list", "--system", "--columns=name,url"])
          .and_return("flathub\thttps://dl.flathub.org/repo/\n")
        expect(dumper.packages_with_remotes).to eql([
          { name: "org.example.App", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        ])
      end
    end
  end

  describe "installing" do
    context "when Flatpak is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "fails with installation guidance without attempting installation" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("org.example.App")).to be(true)
        expect { expect(described_class.install!("org.example.App")).to be(false) }
          .to output(/flatpak is not installed.*distribution's package manager/).to_stderr
      end
    end

    describe "native batches" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("flatpak"))
      end

      it "installs refs sharing a remote in one batch" do
        entries = [
          Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.example.App", remote: "flathub"),
          Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.example.OtherApp", remote: "flathub"),
        ]
        expect(described_class.batch_installable?("org.example.App", remote: "flathub")).to be(true)
        expect(Homebrew::Bundle).to receive(:system)
          .with("flatpak", "install", "-y", "--system", "flathub",
                "org.example.App", "org.example.OtherApp", verbose: false)
          .and_return(true)

        expect(described_class.install_batch!(entries, verbose: false)).to be(true)
      end

      it "does not batch entries that need their own remote" do
        expect(described_class.batch_installable?(
                 "org.example.SourceApp",
                 remote: "https://example.com/beta-repo/",
               )).to be(false)
      end
    end

    context "when Flatpak is installed", :needs_linux do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("flatpak"))
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return([{ name: "org.example.App", remote: "flathub" }])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("org.example.App")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([])
        end

        describe "Tier 1: no URL (flathub default)" do
          it "installs package from flathub" do
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "flathub", "org.example.App",
                                    verbose: false)
                              .and_return(true)
            expect(described_class.preinstall!("org.example.App")).to be(true)
            expect(described_class.install!("org.example.App")).to be(true)
          end

          it "installs package from named remote" do
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "example-remote", "org.example.App",
                                    verbose: false)
                              .and_return(true)
            expect(described_class.preinstall!("org.example.App", remote: "example-remote")).to be(true)
            expect(described_class.install!("org.example.App", remote: "example-remote")).to be(true)
          end
        end

        describe "Tier 2: URL only (single-app remote)" do
          it "creates single-app remote with -origin suffix" do
            allow(described_class).to receive(:get_remote_url).and_return(nil)

            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system",
                                    "--no-gpg-verify", "org.example.SourceApp-origin",
                                    "https://example.com/beta-repo/", verbose: false)
                              .and_return(true)
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "org.example.SourceApp-origin",
                                    "org.example.SourceApp", verbose: false)
                              .and_return(true)

            expect(described_class.preinstall!("org.example.SourceApp", remote: "https://example.com/beta-repo/"))
              .to be(true)
            expect(described_class.install!("org.example.SourceApp", remote: "https://example.com/beta-repo/"))
              .to be(true)
          end

          it "replaces single-app remote when URL changes" do
            allow(described_class).to receive(:get_remote_url)
              .with(anything, "org.example.SourceApp-origin")
              .and_return("https://old.url/repo/")

            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "remote-delete", "--system", "--force",
                                    "org.example.SourceApp-origin", verbose: false)
                              .and_return(true)
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system",
                                    "--no-gpg-verify", "org.example.SourceApp-origin",
                                    "https://example.com/beta-repo/", verbose: false)
                              .and_return(true)
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "org.example.SourceApp-origin",
                                    "org.example.SourceApp", verbose: false)
                              .and_return(true)

            expect(described_class.install!("org.example.SourceApp", remote: "https://example.com/beta-repo/"))
              .to be(true)
          end

          it "installs from .flatpakref directly" do
            allow(described_class).to receive(:command_output)
              .with("flatpak", args: ["list", "--app", "--columns=application,origin"])
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
                                    "example-beta", "https://example.com/beta-repo/", verbose: false)
                              .and_return(true)
            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "example-beta",
                                    "org.example.SourceApp", verbose: false)
                              .and_return(true)

            expect(described_class.install!("org.example.SourceApp",
                                            remote: "example-beta",
                                            url:    "https://example.com/beta-repo/"))
              .to be(true)
          end

          it "warns but uses existing remote with different URL" do
            allow(described_class).to receive(:get_remote_url)
              .with(anything, "example-beta")
              .and_return("https://different.url/repo/")

            # Should NOT try to add remote (uses existing)
            expect(Homebrew::Bundle).not_to receive(:system)
              .with("flatpak", "remote-add", any_args)
            # Should NOT try to delete remote (user explicitly named it)
            expect(Homebrew::Bundle).not_to receive(:system)
              .with("flatpak", "remote-delete", any_args)

            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "example-beta",
                                    "org.example.SourceApp", verbose: false)
                              .and_return(true)

            expect(described_class.install!("org.example.SourceApp",
                                            remote: "example-beta",
                                            url:    "https://example.com/beta-repo/"))
              .to be(true)
          end

          it "reuses existing shared remote when URL matches" do
            allow(described_class).to receive(:get_remote_url)
              .with(anything, "example-beta")
              .and_return("https://example.com/beta-repo/")

            # Should NOT try to add remote (already exists with same URL)
            expect(Homebrew::Bundle).not_to receive(:system)
              .with("flatpak", "remote-add", any_args)

            expect(Homebrew::Bundle).to \
              receive(:system).with("flatpak", "install", "-y", "--system", "example-beta",
                                    "org.example.SourceApp", verbose: false)
                              .and_return(true)

            expect(described_class.install!("org.example.SourceApp",
                                            remote: "example-beta",
                                            url:    "https://example.com/beta-repo/"))
              .to be(true)
          end
        end
      end
    end

    describe ".generate_single_app_remote_name" do
      it "generates name with -origin suffix" do
        expect(described_class.generate_single_app_remote_name("org.example.SourceApp"))
          .to eq("org.example.SourceApp-origin")
      end

      it "handles various app ID formats" do
        expect(described_class.generate_single_app_remote_name("com.example.App"))
          .to eq("com.example.App-origin")
      end
    end
  end
end
