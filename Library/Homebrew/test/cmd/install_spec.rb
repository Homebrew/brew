# typed: false
# frozen_string_literal: true

require "cmd/install"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::InstallCmd do
  include FileUtils

  it_behaves_like "parseable arguments"

  it "installs an explicitly requested tap before resolving a formula" do
    cmd = described_class.new(["user/repo/foo"])
    tap = Tap.fetch("user", "repo")

    allow(Tap).to receive(:with_formula_name).with("user/repo/foo").and_return([tap, "foo"])
    expect(tap).to receive(:ensure_installed!).ordered
    expect(cmd.args.named).to receive(:to_formulae_and_casks).with(warn: false).ordered
                                                             .and_raise(TapFormulaUnavailableError.new(tap, "foo"))

    expect { cmd.run }.to output(/If you trust this tap/).to_stderr

    expect(Homebrew).to have_failed
  end

  it "does not install `homebrew/cask` when a cask remains unavailable" do
    cmd = described_class.new(["foo"])
    cask_tap = CoreCaskTap.instance

    require "search"

    allow(Tap).to receive_messages(with_formula_name: nil, with_cask_token: nil, untapped_official_taps: [])
    allow(cmd.args.named).to receive(:to_formulae_and_casks).with(warn: false)
                                                            .and_raise(FormulaOrCaskUnavailableError.new("foo"))
    allow(cask_tap).to receive(:installed?).and_return(false)
    allow(Homebrew::Search).to receive(:search_names).and_return([[], []])

    expect(cask_tap).not_to receive(:ensure_installed!)

    expect { cmd.run }.to raise_error(SystemExit)

    expect(Homebrew).to have_failed
  end

  context "when using a bottle" do
    let(:formula_name) { "testball_bottle" }
    let(:formula_prefix) { HOMEBREW_CELLAR/formula_name/"0.1" }
    let(:formula_prefix_regex) { /#{Regexp.escape(formula_prefix)}/o }
    let(:option_file) { formula_prefix/"foo/test" }
    let(:bottle_file) { formula_prefix/"bin/helloworld" }

    it "installs a Formula", :integration_test do
      setup_test_formula formula_name

      expect { brew "install", formula_name }
        .to output(formula_prefix_regex).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).not_to be_a_file
      expect(bottle_file).to be_a_file

      uninstall_test_formula formula_name

      expect { brew "install", "--ask", formula_name }
        .to output(/.*Formula\s*\(1\):\s*#{formula_name}.*/).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).not_to be_a_file
      expect(bottle_file).to be_a_file

      uninstall_test_formula formula_name

      expect { brew "install", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
        .to not_to_output(formula_prefix_regex).to_stdout
        .and output(/#{formula_name} was forbidden/).to_stderr
        .and be_a_failure
      expect(formula_prefix).not_to exist
    end

    it "installs a keg-only Formula", :integration_test do
      setup_test_formula formula_name, <<~RUBY
        keg_only "test reason"
      RUBY

      expect { brew "install", formula_name }
        .to output(formula_prefix_regex).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).not_to be_a_file
      expect(bottle_file).to be_a_file
      expect(HOMEBREW_PREFIX/"bin/helloworld").not_to be_a_file
    end
  end

  context "when building from source" do
    let(:formula_name) { "testball1" }

    it "installs a Formula", :integration_test do
      formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
      formula_prefix_regex = /#{Regexp.escape(formula_prefix)}/o
      option_file = formula_prefix/"foo/test"
      always_built_file = formula_prefix/"bin/test"

      setup_test_formula formula_name

      expect { brew "install", formula_name, "--with-foo" }
        .to output(formula_prefix_regex).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).to be_a_file
      expect(always_built_file).to be_a_file

      uninstall_test_formula formula_name

      expect { brew "install", formula_name, "--debug-symbols", "--build-from-source" }
        .to output(formula_prefix_regex).to_stdout
        .and output(/✔︎.*/m).to_stderr
        .and be_a_success
      expect(option_file).not_to be_a_file
      expect(always_built_file).to be_a_file
      expect(formula_prefix/"bin/test.dSYM/Contents/Resources/DWARF/test").to be_a_file if OS.mac?
      expect(HOMEBREW_CACHE/"Sources/#{formula_name}").to be_a_directory
    end

    it "installs a HEAD Formula", :integration_test do
      testball1_prefix = HOMEBREW_CELLAR/"testball1/HEAD-d5eb689"
      repo_path = HOMEBREW_CACHE/"repo"
      (repo_path/"bin").mkpath

      repo_path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-foo"
        FileUtils.touch "bin/something.bin"
        FileUtils.touch "README"
        system "git", "add", "--all"
        system "git", "commit", "-m", "Initial repo commit"
      end

      setup_test_formula "testball1", <<~RUBY
        version "1.0"

        head "file://#{repo_path}", using: :git

        def install
          prefix.install Dir["*"]
        end
      RUBY

      expect { brew "install", formula_name, "--HEAD", "HOMEBREW_DOWNLOAD_CONCURRENCY" => "1" }
        .to output(/#{Regexp.escape(testball1_prefix)}/o).to_stdout
        .and output(/Cloning into/).to_stderr
        .and be_a_success
      expect(testball1_prefix/"foo/test").not_to be_a_file
      expect(testball1_prefix/"bin/something.bin").to be_a_file
    end
  end

  it "prints a shared fetch heading and correct upgrade count", :cask do
    cmd = described_class.new(["codex"])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
    formula = formula("testball_bottle") { url "https://brew.sh/testball_bottle-0.1.tar.gz" }
    formula_installer = instance_double(FormulaInstaller, formula:)
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    installer = instance_double(Cask::Installer, prelude: nil, enqueue_downloads: nil)

    allow(Tap).to receive_messages(with_formula_name: nil, with_cask_token: nil)
    allow(cmd.args.named).to receive(:to_formulae_and_casks).with(warn: false).and_return([formula, cask])
    allow(cask).to receive_messages(
      installed?:        true,
      full_name:         "codex",
      installed_version: "0.117.0",
      version:           "0.118.0",
    )
    allow(Cask::Upgrade).to receive(:outdated_casks).and_return([cask])
    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(Homebrew::Install).to receive(:install_formula?).and_return(true)
    allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
    allow(Homebrew::Install).to receive(:check_cc_argv)
    allow(Homebrew::Upgrade).to receive(:dependants).and_return(Homebrew::Upgrade::Dependents.new(
                                                                  upgradeable: [],
                                                                  pinned:      [],
                                                                  skipped:     [],
                                                                ))
    allow(Homebrew::Install).to receive_messages(
      formula_installers: [formula_installer],
      enqueue_formulae:   [formula_installer],
    )
    allow(Cask::Installer).to receive(:new).and_return(installer)
    allow(Homebrew::Install).to receive(:install_formulae)
    allow(Homebrew::Upgrade).to receive(:upgrade_dependents)
    allow(Homebrew::Cleanup).to receive(:periodic_clean!)
    allow(Homebrew.messages).to receive(:display_messages)
    allow(Cask::Upgrade).to receive(:upgrade_casks!) do |*_, **kwargs|
      expect(kwargs[:skip_prefetch]).to be(true)
      expect(kwargs[:show_upgrade_summary]).to be(false)

      true
    end

    expect { cmd.run }.to output(<<~EOS).to_stdout
      ==> Upgrading 1 outdated package:
      codex 0.117.0 -> 0.118.0
      ==> Fetching downloads for: testball_bottle and codex
    EOS
  end
end
