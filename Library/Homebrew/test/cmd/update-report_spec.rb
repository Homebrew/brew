# frozen_string_literal: true

require "cmd/update-report"
require "formula_versions"
require "yaml"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::UpdateReport do
  it_behaves_like "parseable arguments"

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
      expect(hub.select_formula_or_cask(:R)).to eq([["cv", "progress"]])
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
        expect(hub.select_formula_or_cask(:R)).to be_empty
      end

      specify "with renamed Formula and restructured Tap" do
        allow(tap).to receive(:formula_renames).and_return("xchat" => "xchat2")
        perform_update("update_git_diff_output_with_formula_rename_and_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.select_formula_or_cask(:R)).to eq([%w[foo/bar/xchat foo/bar/xchat2]])
      end

      specify "with simulated 'homebrew/php' restructuring" do
        perform_update("update_git_diff_simulate_homebrew_php_restructuring")

        expect(hub.select_formula_or_cask(:A)).to be_empty
        expect(hub.select_formula_or_cask(:D)).to be_empty
        expect(hub.select_formula_or_cask(:R)).to be_empty
      end

      specify "with Formula changes" do
        perform_update("update_git_diff_output_with_tap_formulae_changes")

        expect(hub.select_formula_or_cask(:A)).to eq(%w[foo/bar/lua])
        expect(hub.select_formula_or_cask(:M)).to eq(%w[foo/bar/git])
        expect(hub.select_formula_or_cask(:D)).to be_empty
      end
    end
  end
end
