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
      expect(hub.instance_variable_get(:@hash)[:R]).to eq([["cv", "progress"]])
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
        expect(hub.instance_variable_get(:@hash)[:R]).to be_nil
      end

      specify "with renamed Formula and restructured Tap" do
        allow(tap).to receive(:formula_renames).and_return("xchat" => "xchat2")
        perform_update("update_git_diff_output_with_formula_rename_and_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.instance_variable_get(:@hash)[:R]).to eq([%w[foo/bar/xchat foo/bar/xchat2]])
      end

      specify "with simulated 'homebrew/php' restructuring" do
        perform_update("update_git_diff_simulate_homebrew_php_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.instance_variable_get(:@hash)[:R]).to be_nil
      end

      specify "with Formula changes" do
        perform_update("update_git_diff_output_with_tap_formulae_changes")

        expect(hub.select_formula_or_cask(:A)).to eq(%w[foo/bar/lua])
        expect(hub.select_formula_or_cask(:M)).to eq(%w[foo/bar/git])
        expect(hub.instance_variable_get(:@hash)[:R]).to be_nil
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
        expect { reporter.send(:ensure_trusted_tap_installed!, "oldfoo", "newfoo", other_tap) }
          .to output(%r{brew trust foo/bar/newfoo.*brew migrate oldfoo}m).to_stderr
      end

      it "recommends a reinstall for an unchanged-name tap migration" do
        expect { reporter.send(:ensure_trusted_tap_installed!, "foo", "foo", other_tap) }
          .to output(/brew reinstall foo/).to_stderr
      end

      it "taps a trusted tap" do
        allow(other_tap).to receive(:official?).and_return(true)
        expect(other_tap).to receive(:ensure_installed!)
        reporter.send(:ensure_trusted_tap_installed!, "foo", "foo", other_tap)
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

          expect(reporter.send(:diff)).to eq(<<~DIFF.strip)
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

          expect(reporter.send(:diff)).to eq(<<~DIFF.strip)
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

    it "prints nothing if there are no changes" do
      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      expect { hub.dump }.not_to output.to_stdout
    end

    it "merges frozen report arrays" do
      first_reporter = instance_double(Reporter, report: { A: ["foo"].freeze })
      second_reporter = instance_double(Reporter, report: { A: ["bar"] })

      hub.add(first_reporter)
      hub.add(second_reporter)

      expect(hub.instance_variable_get(:@hash)[:A]).to eq(%w[foo bar])
    end
  end
end
