# typed: strict
# frozen_string_literal: true

require "cli/named_args"
require "cmd/shared_examples/args_parse"
require "cmd/uses"
require "fileutils"

RSpec.describe Homebrew::Cmd::Uses do
  include FileUtils

  it_behaves_like "parseable arguments"

  it "finds Formulae that use a given Formula", :integration_test, :no_api do
    setup_test_formula "foo"
    setup_test_formula "bar"

    expect { brew "uses", "foo" }
      .to output("bar\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "evaluates all trusted formulae" do
    used_formula = instance_double(Formula, full_name: "foo")
    cmd = described_class.new(["--formula", "foo"])

    allow(cmd.args.named).to receive(:to_formulae).and_return([used_formula])
    expect(Formula).to receive(:all).and_return([])

    expect { cmd.run }.to not_to_output.to_stderr
  end

  context "when core formulae come from the API" do
    before do
      allow(CoreTap.instance).to receive(:installed?).and_return(false)
      allow(Homebrew::EnvConfig).to receive(:no_install_from_api?).and_return(false)
      allow(Homebrew::API::Internal).to receive_messages(formula_aliases: {}, formula_renames: {})
      allow(Formula).to receive(:core_names).and_return(%w[bar baz foo])
    end

    it "loads only the formulae whose API data names the used formula" do
      cmd = described_class.new(["--formula", "foo"])
      allow(cmd.args.named).to receive(:to_formulae)
        .and_return([instance_double(Formula, name: "foo", full_name: "foo")])
      allow(Homebrew::API::Internal).to receive(:formula_names_including)
        .with(["\"foo\"", "/foo\""])
        .and_return(["bar"])

      expect(Formula).to receive(:all).with(core_names: ["bar"]).and_return([])
      cmd.run
    end

    it "loads every core formula when including build dependencies" do
      cmd = described_class.new(["--formula", "--include-build", "foo"])
      allow(cmd.args.named).to receive(:to_formulae)
        .and_return([instance_double(Formula, name: "foo", full_name: "foo")])

      expect(Formula).to receive(:all).with(core_names: %w[bar baz foo]).and_return([])
      cmd.run
    end

    it "loads every core formula when the used formula can be an implicit dependency" do
      cmd = described_class.new(["--formula", "foo"])
      allow(cmd.args.named).to receive(:to_formulae)
        .and_return([instance_double(Formula, name: "foo", full_name: "foo")])
      allow(DependencyCollector).to receive(:new)
        .and_return(instance_double(DependencyCollector, implicit_dependency_names: Set["foo"]))

      expect(Formula).to receive(:all).with(core_names: %w[bar baz foo]).and_return([])
      cmd.run
    end
  end

  it "handles unavailable formula" do
    cmd = described_class.new(%w[foo --include-optional --recursive])
    allow(cmd.args.named)
      .to receive(:to_formulae)
      .and_raise(FormulaUnavailableError, "foo")
    allow(cmd).to receive(:intersection_of_dependents)
      .and_return([
        instance_double(Formula, full_name: "bar"),
        instance_double(Formula, full_name: "optional"),
      ])

    allow(Homebrew::Trust).to receive(:trusted?).and_return(true)

    expect { cmd.run }
      .to output(/^(?:bar\noptional|optional\nbar)$/).to_stdout
      .and output(/Error: Missing formulae should not have dependents!\n/).to_stderr
      .and raise_error SystemExit
  end
end
