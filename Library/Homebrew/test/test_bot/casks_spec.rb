# typed: strict
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::Casks, :cask do
  sig { returns(Homebrew::TestBot::Casks) }
  subject(:runner) { described_class.new }

  sig { returns(Cask::Cask) }
  let(:cask) { Cask::CaskLoader.load("local-caffeine") }

  before do
    allow(GitHub::Actions).to receive(:env_set?).and_return(false)
    allow(SystemCommand).to receive(:run).and_call_original
    success = instance_double(SystemCommand::Result, success?: true, merged_output: "")
    allow(SystemCommand).to receive(:run).with("brew", any_args).and_return(success)
    stub_cask_loader cask, call_original: true
    allow(Utils::Bottles).to receive(:tag).and_return(Utils::Bottles::Tag.from_symbol(:arm64_tahoe))
  end

  it "plans conflict removal, audit and installation in a macOS dry run" do
    installer = instance_double(Cask::Installer, installed_conflicts: ["old-caffeine"])
    allow(Cask::Installer).to receive(:new).and_return(installer)
    expect(Cask::CI::Check).not_to receive(:all)

    args = Homebrew::Cmd::TestBotCmd.new(%w[--dry-run --cleanup]).args
    phase = described_class.new(dry_run: true)
    phase.run!([cask.token], added_casks: [cask.token], args:)

    expect(phase.steps.first&.command).to eq(%w[brew fetch --cask --retry local-caffeine --force])
    expect(phase.steps.map(&:command_short))
      .to include("audit --cask local-caffeine --online --new", "uninstall --cask old-caffeine",
                  "install --cask local-caffeine", "Check uninstall local-caffeine")
  end

  it "reinstalls a formula removed by a conflict and records its post-install failures", :integration_test do
    ENV.delete("HOMEBREW_NO_AUTOREMOVE")
    setup_test_formula "testball_bottle", 'post_install_steps { run "/usr/bin/false" }'
    {
      "needs-testball"     => ['depends_on formula: "testball_bottle"', 'installer manual: "Caffeine.app"'],
      "conflicts-testball" => ['conflicts_with cask: "needs-testball"', "stage_only true"],
    }.each do |token, (dependency, artifact)|
      (CoreCaskTap.instance.cask_dir/"#{token}.rb").write <<~RUBY
        cask "#{token}" do
          version "1"
          sha256 :no_check
          url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
          #{dependency}
          #{artifact}
        end
      RUBY
    end
    allow(Utils::Bottles).to receive(:tag).and_return(Utils::Bottles::Tag.from_symbol(:x86_64_linux))
    install_commands = start_with("install").or(start_with("uninstall"))
    allow(SystemCommand).to receive(:run).with("brew", hash_including(args: install_commands)) do |_, args:, env:, **|
      instance_double(SystemCommand::Result, success?: brew(*args, env.dup).success?, merged_output: "")
    end

    args = Homebrew::Cmd::TestBotCmd.new(["--cleanup"]).args
    expect { runner.run!(%w[needs-testball conflicts-testball needs-testball], added_casks: [], args:) }
      .to output(/post-install step did not complete.*post-install step did not complete/m).to_stderr
    expect(runner.failed_steps.map(&:command_short)).to eq(["install --cask needs-testball"] * 2)
    expect(runner.steps.select(&:passed?).map(&:command_short)).to include("uninstall --cask needs-testball")
    expect(Tab.for_formula(Formula["testball_bottle"]).poured_from_bottle).to be(true)
  end

  it "continues after conflicts and dependency errors and installs with API formulae and checked-out casks" do
    (CoreCaskTap.instance.cask_dir/"with-caffeine.rb").write('cask("with-caffeine") { sha256 :invalid }')
    ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
    allow(CoreTap.instance).to receive(:path).and_return(mktmpdir/"absent-core")
    expect(CoreTap.instance).not_to receive(:install)
    Homebrew::API::Internal.clear_cache
    wget = { "desc" => "wget", "homepage" => "https://brew.sh", "license" => "GPL-3.0-only", "stable_version" => "1",
             "stable_url_args" => ["https://brew.sh/wget"], "ruby_source_checksum" => "0"*64 }
    api = Hash.new { {} }.merge("formulae" => { "wget" => wget }, "formula_tap_git_head" => "0"*40,
                                "casks" => { "local-transmission-zip" => {} })
    expect(Homebrew::API::Internal).to receive(:fetch_packages_api!).and_return([api, false])
    allow(cask.depends_on).to receive(:formula).and_return(["wget"])
    (CoreCaskTap.instance.cask_dir/"local-transmission-zip.rb").unlink
    allow(Cask::CI::ZapCheck).to receive(:run).with(cask.sourcefile_path.to_s).and_raise("cannot open app")
    after = { installed_apps: ["Leftover.app"] }
    allow(Cask::CI::Check).to receive(:all).and_return({}, after)
    allow(Cask::CI::Check).to receive(:errors).with({}, after, cask:).and_return(["Leftover.app"])

    args = Homebrew::Cmd::TestBotCmd.new(["--cleanup"]).args
    runner.run!(%w[with-conflicts-with-multiple with-depends-on-cask local-caffeine], added_casks: [], args:)

    expect(runner.ignored_steps.map(&:output)).to eq(["cannot open app"])
    expect(runner.failed_steps.map(&:output)).to match([/invalid 'sha256'/, /local-transmission-zip/, "Leftover.app"])
    expect(runner.failed_steps.fetch(0).command).to eq(["Resolve conflicts", "with-conflicts-with-multiple"])
    expect(runner.steps.map(&:command_short)).not_to include("uninstall --cask --zap with-conflicts-with-multiple",
                                                             "install --cask with-depends-on-cask")
  end

  test_each([false, true]) do |dry_run|
    it "records a load error and tests the next supported cask with dry_run=#{dry_run}" do
      (CoreCaskTap.instance.cask_dir/"broken.rb").write('cask("broken") { unknown_stanza 1 }')
      allow(cask).to receive(:sha256).and_return(nil)
      args = Homebrew::Cmd::TestBotCmd.new(%w[--only-casks --skip-install --skip-livecheck --except=signing]).args
      runner = described_class.new(dry_run:)
      runner.run!(%w[broken with-depends-on-linux-bare local-caffeine], added_casks: [], args:)

      expect(runner.failed_steps.map(&:output)).to contain_exactly(/undefined method 'unknown_stanza'/)
      expect(runner.steps.map(&:command)).to eq([
        ["Load cask", "broken"],
        %w[brew fetch --cask --retry local-caffeine],
        ["brew", "audit", "--cask", cask.token, "--online",
         "--except=signing,hosting_with_livecheck,livecheck_https_availability,livecheck_version,min_os"],
      ])
    end
  end

  it "reports audit results after a failed fetch and skips installation" do
    failed = instance_double(SystemCommand::Result, success?: false, merged_output: "")
    allow(SystemCommand).to receive(:run).with("brew", hash_including(args: start_with("fetch"))).and_return(failed)
    runner.run!([cask.token], added_casks: [], args: Homebrew::Cmd::TestBotCmd.new([]).args)

    expect(runner.steps.map { |step| [step.name, step.status] }).to eq([["fetch", :failed], ["audit", :passed]])
  end

  it "resolves a third-party cask's core dependency through the API without a cask checkout", :trust_store do
    tap = Tap.fetch("third-party/tap")
    Homebrew::Trust.trust!(:tap, tap)
    root = Cask::CaskLoader.load("third-party/tap/third-party-cask")
    allow(root.depends_on).to receive(:cask).and_return(["api-only"])
    stub_cask_loader root, root.full_name
    allow(CoreCaskTap.instance).to receive(:path).and_return(mktmpdir/"absent-cask")
    ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
    Homebrew::API::Internal.clear_cache
    api = Hash.new { {} }.merge("casks" => { "api-only" => { "version" => "1" } }, "cask_tap_git_head" => "0"*40)
    expect(Homebrew::API::Internal).to receive(:fetch_packages_api!).and_return([api, false])
    installer = Cask::Installer.new(root)
    allow(installer).to receive(:primary_container).and_return(instance_double(UnpackStrategy::Zip, dependencies: []))
    allow(Cask::Installer).to receive(:new).with(root, verbose: false).and_return(installer)

    runner = described_class.new(tap:)
    runner.run!([root.token], added_casks: [root.token], args: Homebrew::Cmd::TestBotCmd.new([]).args)
    expect(runner.failed_steps.map(&:output)).to be_empty
    expect(runner.steps.map(&:command)).to include(["brew", "audit", "--cask", root.full_name, "--online", "--new"])
  end

  test_each([:never_installed, :partially_installed, :already_installed]) do |state|
    it "cleans up dependencies in reverse order after a failed install (#{state})" do
      allow(cask).to receive(:installed?).and_return(state == :already_installed, state != :never_installed)
      dependencies = %w[runtime plugin absent].map { |token| Cask::Cask.new(token) }
      dependencies.first(2).each { |dependency| allow(dependency).to receive(:installed?).and_return(true) }
      installer = instance_double(Cask::Installer, missing_cask_and_formula_dependencies: dependencies)
      failure = instance_double(SystemCommand::Result, success?: false, merged_output: +"installation failed")
      allow(SystemCommand).to receive(:run).with("brew", hash_including(args: start_with("install"))) { failure }
      allow(Cask::Installer).to receive(:new).with(cask, verbose: false).and_return(installer)
      runner.run!(["local-caffeine"], added_casks: [], args: Homebrew::Cmd::TestBotCmd.new([]).args)

      removed = T.let([%w[brew uninstall --cask plugin runtime]], T::Array[T::Array[String]])
      removed.unshift(%w[brew uninstall --cask local-caffeine]) if state == :partially_installed
      expect(runner.steps.map(&:command).select { |command| command[1] == "uninstall" }).to eq(removed)
    end
  end
end
