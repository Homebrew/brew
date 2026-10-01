# typed: strict
# frozen_string_literal: true

require "cmd/leaves"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Leaves do
  it_behaves_like "parseable arguments"

  context "when there are no installed Formulae" do
    it "prints nothing" do
      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      expect { described_class.new([]).run }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
    end
  end

  context "when there are only installed Formulae without dependencies" do
    it "prints all installed Formulae" do
      allow(Formula).to receive(:installed).and_return([
        instance_double(
          Formula,
          any_installed_keg:                      nil,
          full_name:                              "foo",
          installed_runtime_formula_dependencies: [],
          possible_names:                         ["foo"],
        ),
      ])
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      expect { described_class.new([]).run }
        .to output("foo\n").to_stdout
        .and not_to_output.to_stderr
    end
  end

  context "when there are installed Formulae", :no_api do
    it "prints all installed Formulae that are not dependencies of another installed Formula", :integration_test do
      setup_test_formula "foo"
      setup_test_formula "bar"
      (HOMEBREW_CELLAR/"foo/0.1/somedir").mkpath
      (HOMEBREW_CELLAR/"bar/0.1/somedir").mkpath

      expect { brew "leaves" }
        .to output("bar\n").to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    it "does not list a renamed formula as a leaf when a stale tab records its old name" do
      # Simulate: "foo" was renamed to "newname"; "bar" depends on it but its tab
      # still records the old dependency name under a tap-qualified full_name
      # (not yet regenerated after rename). Also exercises the tap-prefix strip path.
      allow(Formula).to receive(:installed).and_return([
        instance_double(
          Formula,
          any_installed_keg:                      nil,
          full_name:                              "newname",
          installed_runtime_formula_dependencies: [],
          possible_names:                         %w[newname foo],
        ),
        instance_double(
          Formula,
          any_installed_keg:                      instance_double(
            Keg,
            runtime_dependencies: [{ "full_name" => "homebrew/core/foo" }],
          ),
          full_name:                              "bar",
          installed_runtime_formula_dependencies: [],
          possible_names:                         ["bar"],
        ),
      ])
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      expect { described_class.new([]).run }
        .to output("bar\n").to_stdout
        .and not_to_output.to_stderr
    end
  end
end
