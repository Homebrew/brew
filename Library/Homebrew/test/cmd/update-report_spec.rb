# typed: true
# frozen_string_literal: true

require "cmd/update-report"
require "formula_versions"
require "yaml"
require "cmd/shared_examples/args_parse"
require "cmd/shared_examples/reinstall_pkgconf_if_needed"

RSpec.describe Homebrew::Cmd::UpdateReport do
  it_behaves_like "parseable arguments"

  it_behaves_like "reinstall_pkgconf_if_needed"

  it "links to the donations section" do
    allow(Homebrew::Settings).to receive(:read).with("donationmessage").and_return("false")

    expect { described_class.new([]).donation_message }
      .to output(include("https://github.com/Homebrew/brew#-donations")).to_stdout
  end

  # Simulate update.sh after a redirected fetch has advanced HEAD and origin/<branch>.
  def setup_redirected_tap(name)
    tap = Tap.fetch("allowed", name)
    tap.path.mkpath
    system "git", "-C", tap.path.to_s, "init"
    system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://allowed.example/homebrew-#{name}"
    (tap.path/"before").write("before")
    system "git", "-C", tap.path.to_s, "add", "--all"
    system "git", "-C", tap.path.to_s, "commit", "-q", "-m", "before"
    before_revision = Utils.popen_read("git", "-C", tap.path.to_s, "rev-parse", "HEAD").chomp
    (tap.path/"after").write("after")
    system "git", "-C", tap.path.to_s, "add", "--all"
    system "git", "-C", tap.path.to_s, "commit", "-q", "-m", "after"
    branch = Utils.popen_read("git", "-C", tap.path.to_s, "symbolic-ref", "--short", "HEAD").chomp
    system "git", "-C", tap.path.to_s, "update-ref", "refs/remotes/origin/#{branch}", "HEAD"
    [tap, before_revision, branch]
  end

  def run_quiet_update_report
    with_env(
      HOMEBREW_UPDATE_BEFORE: "abc",
      HOMEBREW_UPDATE_AFTER:  "abc",
      HOMEBREW_UPDATE_TEST:   "1",
    ) { described_class.new(["--quiet"]).run }
  end

  it "copies update revisions for redirected tap names" do
    redirected_remotes_file = mktmpdir/"redirected-remotes"
    redirected_remotes_file.write("/tmp/homebrew-foo\thttps://github.com/new/homebrew-foo.git\n")

    tap = instance_double(Tap, repository_var_suffix: "_OLD_HOMEBREW_FOO")
    allow(Tap).to receive(:from_path).with("/tmp/homebrew-foo").and_return(tap)
    allow(tap).to receive(:apply_redirected_remote!)
      .with("https://github.com/new/homebrew-foo.git", quiet: true) do
        allow(tap).to receive(:repository_var_suffix).and_return("_NEW_HOMEBREW_FOO")
      end
    allow(Homebrew::EnvConfig).to receive_messages(disable_load_formula?: true, no_install_from_api?: true)
    update_report = described_class.new(["--quiet"])
    allow(update_report).to receive(:tap_or_untap_core_taps_if_necessary)

    with_env(
      HOMEBREW_REDIRECTED_REMOTES_FILE:        redirected_remotes_file.to_s,
      HOMEBREW_UPDATE_BEFORE:                  "abc",
      HOMEBREW_UPDATE_AFTER:                   "abc",
      HOMEBREW_UPDATE_BEFORE_OLD_HOMEBREW_FOO: "123",
      HOMEBREW_UPDATE_AFTER_OLD_HOMEBREW_FOO:  "456",
    ) do
      update_report.run

      expect(ENV.fetch("HOMEBREW_UPDATE_BEFORE_NEW_HOMEBREW_FOO")).to eq("123")
      expect(ENV.fetch("HOMEBREW_UPDATE_AFTER_NEW_HOMEBREW_FOO")).to eq("456")
    end
  end

  it "refuses an off-allowlist redirect and rolls the tap back to its pre-update revision" do
    tap, before_revision, branch = setup_redirected_tap("foo")
    redirected_remotes_file = mktmpdir/"redirected-remotes"
    redirected_remotes_file.write("#{tap.path}\thttps://attacker.example/homebrew-foo\n")
    allow(Homebrew::EnvConfig).to receive_messages(allowed_taps: "https://allowed.example/homebrew-foo",
                                                   disable_load_formula?: true, no_install_from_api?: true)
    update_report = described_class.new(["--quiet"])

    with_env(
      "HOMEBREW_REDIRECTED_REMOTES_FILE"                   => redirected_remotes_file.to_s,
      "HOMEBREW_UPDATE_BEFORE"                             => "abc",
      "HOMEBREW_UPDATE_AFTER"                              => "abc",
      "HOMEBREW_UPDATE_BEFORE#{tap.repository_var_suffix}" => before_revision,
    ) do
      expect { update_report.run }.to raise_error(SystemExit)
    end

    expect(Utils.popen_read("git", "-C", tap.path, "rev-parse", "HEAD").chomp).to eq(before_revision)
    expect(Utils.popen_read("git", "-C", tap.path, "rev-parse", "refs/remotes/origin/#{branch}").chomp)
      .to eq(before_revision)
    expect(Utils.popen_read("git", "-C", tap.path, "config", "remote.origin.url").chomp)
      .to eq("https://allowed.example/homebrew-foo")
  ensure
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"allowed"
  end

  it "rolls back every denied tap when several off-allowlist redirects are in the file" do
    foo_tap, foo_before, foo_branch = setup_redirected_tap("foo")
    bar_tap, bar_before, bar_branch = setup_redirected_tap("bar")
    redirected_remotes_file = mktmpdir/"redirected-remotes"
    redirected_remotes_file.write(
      "#{foo_tap.path}\thttps://attacker.example/homebrew-foo\n" \
      "#{bar_tap.path}\thttps://attacker.example/homebrew-bar\n",
    )
    allow(Homebrew::EnvConfig).to receive_messages(
      allowed_taps:          "https://allowed.example/homebrew-foo https://allowed.example/homebrew-bar",
      disable_load_formula?: true,
      no_install_from_api?:  true,
    )
    update_report = described_class.new(["--quiet"])

    with_env(
      "HOMEBREW_REDIRECTED_REMOTES_FILE"                       => redirected_remotes_file.to_s,
      "HOMEBREW_UPDATE_BEFORE"                                 => "abc",
      "HOMEBREW_UPDATE_AFTER"                                  => "abc",
      "HOMEBREW_UPDATE_BEFORE#{foo_tap.repository_var_suffix}" => foo_before,
      "HOMEBREW_UPDATE_BEFORE#{bar_tap.repository_var_suffix}" => bar_before,
    ) do
      expect { update_report.run }.to raise_error(SystemExit)
    end

    expect(Utils.popen_read("git", "-C", foo_tap.path, "rev-parse", "HEAD").chomp).to eq(foo_before)
    expect(Utils.popen_read("git", "-C", foo_tap.path, "rev-parse", "refs/remotes/origin/#{foo_branch}").chomp)
      .to eq(foo_before)
    expect(Utils.popen_read("git", "-C", bar_tap.path, "rev-parse", "HEAD").chomp).to eq(bar_before)
    expect(Utils.popen_read("git", "-C", bar_tap.path, "rev-parse", "refs/remotes/origin/#{bar_branch}").chomp)
      .to eq(bar_before)
  ensure
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"allowed"
  end

  it "rolls back the remote-tracking ref for a denied redirect when HEAD is detached" do
    tap, before_revision, branch = setup_redirected_tap("foo")
    # Detached HEAD makes `symbolic-ref HEAD` empty, so the rollback must fall back to origin/HEAD.
    system "git", "-C", tap.path.to_s, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/#{branch}"
    system "git", "-C", tap.path.to_s, "checkout", "-q", "--detach", "HEAD"
    redirected_remotes_file = mktmpdir/"redirected-remotes"
    redirected_remotes_file.write("#{tap.path}\thttps://attacker.example/homebrew-foo\n")
    allow(Homebrew::EnvConfig).to receive_messages(allowed_taps: "https://allowed.example/homebrew-foo",
                                                   disable_load_formula?: true, no_install_from_api?: true)
    update_report = described_class.new(["--quiet"])

    with_env(
      "HOMEBREW_REDIRECTED_REMOTES_FILE"                   => redirected_remotes_file.to_s,
      "HOMEBREW_UPDATE_BEFORE"                             => "abc",
      "HOMEBREW_UPDATE_AFTER"                              => "abc",
      "HOMEBREW_UPDATE_BEFORE#{tap.repository_var_suffix}" => before_revision,
    ) do
      expect { update_report.run }.to raise_error(SystemExit)
    end

    expect(Utils.popen_read("git", "-C", tap.path, "rev-parse", "HEAD").chomp).to eq(before_revision)
    expect(Utils.popen_read("git", "-C", tap.path, "rev-parse", "refs/remotes/origin/#{branch}").chomp)
      .to eq(before_revision)
  ensure
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"allowed"
  end

  it "migrates supported Caskroom Ruby and internal JSON metadata to JSON for all users" do
    caskroom = mktmpdir/"Caskroom"
    rb_caskfile = caskroom/"local-caffeine/.metadata/1.0/20250101000000.000/Casks/local-caffeine.rb"
    json_caskfile = rb_caskfile.sub_ext(".json")
    uninstall_flight_caskfile =
      caskroom/"with-uninstall-preflight/.metadata/1.0/20250101000000.000/Casks/with-uninstall-preflight.rb"
    receiptless_caskfile =
      caskroom/"receiptless-cask/.metadata/1.0/20250101000000.000/Casks/receiptless-cask.rb"
    receiptless_json_caskfile = receiptless_caskfile.sub_ext(".json")
    internal_json_caskfile = caskroom/"api-cask/.metadata/1.0/20250101000000.000/Casks/api-cask.internal.json"
    api_caskfile = internal_json_caskfile.dirname/"api-cask.json"
    rb_caskfile.dirname.mkpath
    rb_caskfile.write <<~RUBY
      cask "local-caffeine" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/local-caffeine.zip"
        name "Local Caffeine"
        homepage "https://example.com/local-caffeine"
        app "Caffeine.app"
      end
    RUBY
    uninstall_flight_caskfile.dirname.mkpath
    uninstall_flight_caskfile.write <<~RUBY
      cask "with-uninstall-preflight" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/with-uninstall-preflight.zip"
        name "With Uninstall Preflight"
        homepage "https://example.com/with-uninstall-preflight"
        app "With Uninstall Preflight.app"

        uninstall_preflight do
          # do nothing
        end
      end
    RUBY
    receiptless_caskfile.dirname.mkpath
    receiptless_caskfile.write <<~RUBY
      cask "receiptless-cask" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/receiptless-cask.zip"
        name "Receipt-less Cask"
        homepage "https://example.com/receiptless-cask"
        app "Receipt-less Cask.app"

        uninstall quit: "com.example.receiptless-cask"
        zap trash: "~/Library/Preferences/com.example.receiptless-cask.plist"
      end
    RUBY
    (caskroom/"local-caffeine/.metadata/INSTALL_RECEIPT.json").write JSON.pretty_generate({
      "source"              => { "version" => "1.0" },
      "uninstall_artifacts" => [{ "app" => ["Caffeine.app"] }],
    })
    internal_json_caskfile.dirname.mkpath
    internal_json_caskfile.write JSON.pretty_generate({
      "homepage"      => "https://example.com/api-cask",
      "names"         => ["API Cask"],
      "raw_artifacts" => [[":app", ["API Cask.app"]]],
      "sha256"        => "no_check",
      "url_args"      => ["https://example.com/api-cask.zip"],
      "version"       => "1.0",
    })
    (caskroom/"api-cask/.metadata/INSTALL_RECEIPT.json").write JSON.pretty_generate({
      "source"              => { "version" => "1.0" },
      "uninstall_artifacts" => [{ "app" => ["API Cask.app"] }],
    })

    allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
    allow(Homebrew::EnvConfig).to receive_messages(developer?: false, disable_load_formula?: true,
                                                   no_install_from_api?: true)

    run_quiet_update_report

    loaded_cask = Cask::CaskLoader.load_from_installed_caskfile(json_caskfile)
    loaded_receiptless_cask = Cask::CaskLoader.load_from_installed_caskfile(receiptless_json_caskfile)
    loaded_api_cask = Cask::CaskLoader.load_from_installed_caskfile(api_caskfile)
    expect([
      rb_caskfile.exist?,
      JSON.parse(json_caskfile.read).keys,
      loaded_cask.version.to_s,
      loaded_cask.artifacts.grep(Cask::Artifact::App).count,
      uninstall_flight_caskfile.exist?,
      uninstall_flight_caskfile.sub_ext(".json").exist?,
      Cask::CaskLoader.load_from_installed_caskfile(uninstall_flight_caskfile).uninstall_flight_blocks?,
      receiptless_caskfile.exist?,
      JSON.parse(receiptless_json_caskfile.read).fetch("artifacts"),
      loaded_receiptless_cask.artifacts_list(uninstall_only: true),
      internal_json_caskfile.exist?,
      JSON.parse(api_caskfile.read).keys,
      loaded_api_cask.loaded_from_internal_api?,
      loaded_api_cask.artifacts.grep(Cask::Artifact::App).count,
    ]).to eq([
      false,
      [],
      "1.0",
      1,
      true,
      false,
      true,
      false,
      [
        { "uninstall" => [{ "quit" => "com.example.receiptless-cask" }] },
        { "app" => ["Receipt-less Cask.app"] },
        { "zap" => [{ "trash" => "~/Library/Preferences/com.example.receiptless-cask.plist" }] },
      ],
      [
        { uninstall: [{ quit: "com.example.receiptless-cask" }] },
        { app: ["Receipt-less Cask.app"] },
        { zap: [{ trash: "~/Library/Preferences/com.example.receiptless-cask.plist" }] },
      ],
      false,
      [],
      false,
      1,
    ])
  end

  it "repairs migrated Cask metadata that differs" do
    caskroom = mktmpdir/"Caskroom"
    caskfile = caskroom/"mismatched/.metadata/1.0/20250101000000.000/Casks/mismatched.rb"
    json_caskfile = caskfile.sub_ext(".json")
    caskfile.dirname.mkpath
    caskfile.write <<~RUBY
      cask "mismatched" do
        version "2.0"
        sha256 :no_check
        url "https://example.com/mismatched.zip"
        name "Mismatched"
        homepage "https://example.com/mismatched"
        app "Mismatched.app"
      end
    RUBY
    (caskroom/"mismatched/.metadata/INSTALL_RECEIPT.json").write JSON.pretty_generate({
      "source"              => { "version" => "1.0" },
      "uninstall_artifacts" => [{ "app" => ["Wrong.app"] }],
    })
    allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
    allow(Homebrew::EnvConfig).to receive_messages(developer?: false, disable_load_formula?: true,
                                                   no_install_from_api?: true)

    2.times { run_quiet_update_report }
    migrated_cask = Cask::CaskLoader.load_from_installed_caskfile(json_caskfile)
    expect([
      caskfile.exist?,
      JSON.parse(json_caskfile.read),
      migrated_cask.version.to_s,
      migrated_cask.artifacts_list(uninstall_only: true),
    ]).to eq([
      false,
      {
        "version"   => "2.0",
        "artifacts" => [{ "app" => ["Mismatched.app"] }],
      },
      "2.0",
      [{ app: ["Mismatched.app"] }],
    ])
  end

  it "repairs existing JSON metadata once" do
    caskroom = mktmpdir/"Caskroom"
    caskfile = caskroom/"stubbed/.metadata/1.0/20250101000000.000/Casks/stubbed.json"
    caskfile.dirname.mkpath
    caskfile.write("{}")
    allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
    allow(Homebrew::EnvConfig).to receive_messages(developer?: false, disable_load_formula?: true,
                                                   no_install_from_api?: true)
    allow(Homebrew::API).to receive(:cask_token?).with("stubbed").and_return(true)
    expect(Homebrew::API::Cask).to receive(:cask_json).once.with("stubbed").and_return({
      "artifacts" => [{ "app" => ["Stubbed.app"] }],
    })

    2.times { run_quiet_update_report }
    expect(JSON.parse(caskfile.read)).to eq({
      "artifacts" => [{ "app" => ["Stubbed.app"] }],
    })
  end

  it "migrates the aged Caskroom fixture eras and preserves their artifacts" do
    # The fixture holds installed metadata byte-for-byte as older Homebrew versions wrote it.
    caskroom = Cask::Caskroom.path
    FileUtils.cp_r TEST_FIXTURE_DIR/"cask/aged_caskroom", caskroom
    pre_receipt_rb_caskfile = caskroom/"pre-receipt-rb/.metadata/1.0/20250101000000.000/Casks/pre-receipt-rb.rb"
    pre_receipt_rb_json_caskfile = pre_receipt_rb_caskfile.sub_ext(".json")
    pre_receipt_stubbed_caskfile =
      caskroom/"pre-receipt-stubbed/.metadata/1.0/20250101000000.000/Casks/pre-receipt-stubbed.json"
    receipt_era_stub_caskfile =
      caskroom/"receipt-era-stub/.metadata/1.0/20250101000000.000/Casks/receipt-era-stub.json"
    internal_json_caskfile =
      caskroom/"internal-json/.metadata/1.0/20250101000000.000/Casks/internal-json.internal.json"
    migrated_internal_caskfile = internal_json_caskfile.dirname/"internal-json.json"
    uninstall_flight_caskfile =
      caskroom/"uninstall-flight-block/.metadata/1.0/20250101000000.000/Casks/uninstall-flight-block.rb"
    allow(Homebrew::API).to receive(:cask_token?).with("pre-receipt-stubbed").and_return(true)
    expect(Homebrew::API::Cask).to receive(:cask_json).once.with("pre-receipt-stubbed").and_return({
      "artifacts" => [{ "app" => ["Pre Receipt Stubbed.app"] }],
    })

    described_class.new(["--quiet"]).migrate_caskroom_caskfiles_to_json

    migrated_rb_cask = Cask::CaskLoader.load_from_installed_caskfile(pre_receipt_rb_json_caskfile)
    receipt_era_stub_cask = Cask::CaskLoader.load_from_installed_caskfile(receipt_era_stub_caskfile)
    migrated_internal_cask = Cask::CaskLoader.load_from_installed_caskfile(migrated_internal_caskfile)
    expect([
      pre_receipt_rb_caskfile.exist?,
      JSON.parse(pre_receipt_rb_json_caskfile.read),
      migrated_rb_cask.version.to_s,
      migrated_rb_cask.artifacts_list(uninstall_only: true),
      JSON.parse(pre_receipt_stubbed_caskfile.read),
      JSON.parse(receipt_era_stub_caskfile.read),
      receipt_era_stub_cask.artifacts_list(uninstall_only: true),
      internal_json_caskfile.exist?,
      JSON.parse(migrated_internal_caskfile.read),
      migrated_internal_cask.artifacts_list(uninstall_only: true),
      uninstall_flight_caskfile.exist?,
      uninstall_flight_caskfile.sub_ext(".json").exist?,
      Cask::CaskLoader.load_from_installed_caskfile(uninstall_flight_caskfile).uninstall_flight_blocks?,
    ]).to eq([
      false,
      { "artifacts" => [{ "app" => ["Pre Receipt Rb.app"] }] },
      "1.0",
      [{ app: ["Pre Receipt Rb.app"] }],
      { "artifacts" => [{ "app" => ["Pre Receipt Stubbed.app"] }] },
      {},
      [{ app: ["Receipt Era Stub.app"] }],
      false,
      {},
      [{ app: ["Internal JSON.app"] }],
      true,
      false,
      true,
    ])
  end

  describe Reporter do
    let(:tap) { CoreTap.instance }
    let(:reporter_class) do
      Class.new(described_class) do
        def initialize(tap)
          @tap = tap

          ENV["HOMEBREW_UPDATE_BEFORE#{tap.repository_var_suffix}"] = "12345678"
          ENV["HOMEBREW_UPDATE_AFTER#{tap.repository_var_suffix}"] = "abcdef00"

          super
        end
      end
    end
    let(:reporter) { reporter_class.new(tap) }
    let(:hub) { ReporterHub.new }

    def perform_update(fixture_name = "")
      allow(Formulary).to receive(:factory).and_return(instance_double(Formula, pkg_version: "1.0"))
      allow(FormulaVersions).to receive(:new).and_return(instance_double(FormulaVersions, formula_at_revision: "2.0"))

      diff = YAML.load_file("#{TEST_FIXTURE_DIR}/updater_fixture.yaml")[fixture_name]
      allow(reporter).to receive(:diff).and_return(diff || "")

      hub.add(reporter) if reporter.updated?
    end

    specify "without revision variable" do
      ENV.delete_if { |k, _v| k.start_with? "HOMEBREW_UPDATE" }

      expect do
        described_class.new(tap)
      end.to raise_error(Reporter::ReporterRevisionUnsetError)
    end

    specify "without any changes" do
      perform_update
      expect(hub).to be_empty
    end

    specify "without Formula changes" do
      perform_update("update_git_diff_output_without_formulae_changes")

      expect(hub.select_formula_or_cask(:M)).to be_empty
      expect(hub.select_formula_or_cask(:A)).to be_empty
      expect(hub.select_formula_or_cask(:D)).to be_empty
    end

    specify "with Formula changes" do
      perform_update("update_git_diff_output_with_formulae_changes")

      expect(hub.select_formula_or_cask(:M)).to eq(%w[xar yajl])
      expect(hub.select_formula_or_cask(:A)).to eq(%w[antiword bash-completion ddrescue dict lua])
    end

    specify "with removed Formulae" do
      perform_update("update_git_diff_output_with_removed_formulae")

      expect(hub.select_formula_or_cask(:D)).to eq(%w[libgsasl])
    end

    specify "with changed file type" do
      perform_update("update_git_diff_output_with_changed_filetype")

      expect(hub.select_formula_or_cask(:M)).to eq(%w[elixir])
      expect(hub.select_formula_or_cask(:A)).to eq(%w[libbson])
      expect(hub.select_formula_or_cask(:D)).to eq(%w[libgsasl])
    end

    specify "with renamed Formula" do
      allow(tap).to receive(:formula_renames).and_return("cv" => "progress")
      perform_update("update_git_diff_output_with_formula_rename")

      expect(hub.select_formula_or_cask(:A)).to be_empty
      expect(hub.select_formula_or_cask(:D)).to be_empty
      expect(hub.renamed_formulae).to eq([["cv", "progress"]])
    end

    context "when updating a Tap other than the core Tap" do
      let(:tap) { Tap.fetch("foo", "bar") }

      before do
        (tap.path/"Formula").mkpath
      end

      after do
        FileUtils.rm_r(tap.path.parent)
      end

      specify "with restructured Tap" do
        perform_update("update_git_diff_output_with_restructured_tap")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.renamed_formulae).to be_empty
      end

      specify "with renamed Formula and restructured Tap" do
        allow(tap).to receive(:formula_renames).and_return("xchat" => "xchat2")
        perform_update("update_git_diff_output_with_formula_rename_and_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.renamed_formulae).to eq([%w[foo/bar/xchat foo/bar/xchat2]])
      end

      specify "with simulated 'homebrew/php' restructuring" do
        perform_update("update_git_diff_simulate_homebrew_php_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.renamed_formulae).to be_empty
      end

      specify "with Formula changes" do
        perform_update("update_git_diff_output_with_tap_formulae_changes")

        expect(hub.select_formula_or_cask(:A)).to eq(%w[foo/bar/lua])
        expect(hub.select_formula_or_cask(:M)).to eq(%w[foo/bar/git])
        expect(hub.renamed_formulae).to be_empty
      end

      specify "with formula migrated to cask in same tap" do
        # Setup a tap with both formulae and casks
        (tap.path/"Formula").mkpath
        (tap.path/"Casks").mkpath
        (tap.path/"tap_migrations.json").write <<~JSON
          { "old-formula": "foo/bar/new-cask" }
        JSON

        # Mock that the tap has a cask with the migration target name
        allow(tap).to receive(:cask_tokens).and_return(["new-cask"])

        reporter_instance = reporter_class.new(tap)
        allow(reporter_instance).to receive(:report).and_return({ D: ["foo/bar/old-formula"] })

        # Verify the migration would be detected as formula-to-cask migration
        expect(tap.tap_migrations).to eq({ "old-formula" => "foo/bar/new-cask" })
        expect(tap.cask_tokens).to include("new-cask")
      end
    end

    describe "#ensure_trusted_tap_installed!" do
      let(:other_tap) { Tap.fetch("foo", "bar") }

      before { allow(other_tap).to receive(:installed?).and_return(false) }

      it "recommends trusting just the migrated package then migrating a rename" do
        expect(other_tap).not_to receive(:ensure_installed!)
        expect { reporter.ensure_trusted_tap_installed!("oldfoo", "newfoo", other_tap) }
          .to output(%r{brew trust foo/bar/newfoo.*brew migrate oldfoo}m).to_stderr
      end

      it "recommends a reinstall for an unchanged-name tap migration" do
        expect { reporter.ensure_trusted_tap_installed!("foo", "foo", other_tap) }
          .to output(/brew reinstall foo/).to_stderr
      end

      it "taps a trusted tap" do
        allow(other_tap).to receive(:official?).and_return(true)
        expect(other_tap).to receive(:ensure_installed!)
        reporter.ensure_trusted_tap_installed!("foo", "foo", other_tap)
      end
    end

    describe "#diff" do
      context "when using the API" do
        subject(:reporter) do
          described_class.new(tap,
                              api_names_txt:        Pathname("formula_names.txt"),
                              api_names_before_txt: Pathname("formula_names_before.txt"),
                              api_dir_prefix:       HOMEBREW_CACHE/"api")
        end

        it "ignore lines that haven't changed" do
          expect(Utils).to receive(:popen_read).and_return(<<~DIFF)
            foo
            +bar
            -baz
          DIFF

          expect(reporter.diff).to eq(<<~DIFF.strip)
            A api/bar.rb
            D api/baz.rb
          DIFF
        end

        it "handles moved lines" do
          expect(Utils).to receive(:popen_read).and_return(<<~DIFF)
            +baz
            foo
            +bar
            +baz
            -bar
            -baz
          DIFF

          expect(reporter.diff).to eq(<<~DIFF.strip)
            A api/baz.rb
          DIFF
        end
      end
    end
  end

  describe ReporterHub do
    let(:hub) { described_class.new }

    before do
      ENV["HOMEBREW_NO_COLOR"] = "1"
      allow(hub).to receive(:select_formula_or_cask).and_return([])
    end

    it "dumps new formulae report" do
      allow(hub).to receive(:select_formula_or_cask).with(:A).and_return(["foo", "bar", "baz"])
      allow(hub).to receive_messages(installed?: false, all_formula_json: [
        { "name" => "foo", "desc" => "foobly things" },
        { "name" => "baz", "desc" => "baz desc" },
      ])
      expect { hub.dump }.to output(<<~EOS).to_stdout
        ==> New Formulae
        bar
        baz: baz desc
        foo: foobly things
      EOS
    end

    it "dumps new casks report" do
      allow(hub).to receive(:select_formula_or_cask).with(:AC).and_return(["cask1", "cask2", "foo/tap/cask3"])
      allow(hub).to receive_messages(cask_installed?: false, all_cask_json: [
        { "token" => "cask1", "desc" => "desc1" },
        { "token" => "cask3", "desc" => "desc3" },
      ])
      allow(Cask::Caskroom).to receive(:any_casks_installed?).and_return(true)
      expect { hub.dump }.to output(<<~EOS).to_stdout
        ==> New Casks
        cask1: desc1
        cask2
        cask3
      EOS
    end

    it "dumps deleted installed formulae and casks report" do
      allow(hub).to receive(:select_formula_or_cask).with(:D).and_return(["baz", "foo", "bar"])
      allow(hub).to receive(:installed?).with("baz").and_return(true)
      allow(hub).to receive(:installed?).with("foo").and_return(true)
      allow(hub).to receive(:installed?).with("bar").and_return(true)
      allow(hub).to receive(:select_formula_or_cask).with(:A).and_return([])
      allow(hub).to receive(:select_formula_or_cask).with(:DC).and_return(["cask2", "cask1"])
      allow(hub).to receive(:cask_installed?).with("cask1").and_return(true)
      allow(hub).to receive(:cask_installed?).with("cask2").and_return(true)
      allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_linux?).and_return(false)
      expect { hub.dump }.to output(<<~EOS).to_stdout
        ==> Deleted Installed Formulae
        bar
        baz
        foo
        ==> Deleted Installed Casks
        cask1
        cask2
      EOS
    end

    it "dumps outdated formulae and casks report" do
      allow(Formula).to receive(:installed).and_return([
        instance_double(Formula, name: "foo", outdated?: true),
        instance_double(Formula, name: "bar", outdated?: true),
      ])
      allow(Cask::Caskroom).to receive(:casks).and_return([
        instance_double(Cask::Cask, token: "baz", outdated?: true),
        instance_double(Cask::Cask, token: "qux", outdated?: true),
      ])
      expect { hub.dump }.to output(<<~EOS).to_stdout
        ==> Outdated Formulae
        bar
        foo
        ==> Outdated Casks
        baz
        qux

        You have 2 outdated formulae and 2 outdated casks installed.
        You can upgrade them with brew upgrade
        or list them with brew outdated.
      EOS
    end

    it "skips the outdated count when auto-updating before a zero-argument upgrade or outdated" do
      ENV["HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED"] = "1"
      allow(Formula).to receive(:installed).and_return([
        instance_double(Formula, name: "foo", outdated?: true),
      ])
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      expect { hub.dump(auto_update: true) }.not_to output.to_stdout
    end

    it "prints nothing if there are no changes" do
      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      expect { hub.dump }.not_to output.to_stdout
    end

    it "merges frozen report arrays" do
      allow(hub).to receive(:select_formula_or_cask).and_call_original
      first_reporter = instance_double(Reporter, report: { A: ["foo"].freeze })
      second_reporter = instance_double(Reporter, report: { A: ["bar"] })

      hub.add(first_reporter)
      hub.add(second_reporter)

      expect(hub.select_formula_or_cask(:A)).to eq(%w[foo bar])
    end
  end
end
