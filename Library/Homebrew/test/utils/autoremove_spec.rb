# frozen_string_literal: true

require "utils/autoremove"

RSpec.describe Utils::Autoremove do
  shared_context "with formulae for dependency testing" do
    let(:formula_with_deps) do
      formula "zero" do
        url "zero-1.0"

        depends_on "three" => :build
      end
    end

    let(:first_formula_dep) do
      formula "one" do
        url "one-1.1"
      end
    end

    let(:second_formula_dep) do
      formula "two" do
        url "two-1.1"
      end
    end

    let(:formula_is_build_dep) do
      formula "three" do
        url "three-1.1"
      end
    end

    let(:formulae) do
      [
        formula_with_deps,
        first_formula_dep,
        second_formula_dep,
        formula_is_build_dep,
      ]
    end

    let(:tab_from_keg) { instance_double(Tab) }

    before do
      allow(formula_with_deps).to receive_messages(
        installed_runtime_formula_dependencies: [first_formula_dep, second_formula_dep],
        any_installed_keg:                      instance_double(Keg, tab: tab_from_keg),
      )
      allow(first_formula_dep).to receive_messages(
        installed_runtime_formula_dependencies: [second_formula_dep],
        any_installed_keg:                      instance_double(Keg, tab: tab_from_keg),
      )
      allow(second_formula_dep).to receive_messages(
        installed_runtime_formula_dependencies: [],
        any_installed_keg:                      instance_double(Keg, tab: tab_from_keg),
      )
      allow(formula_is_build_dep).to receive_messages(
        installed_runtime_formula_dependencies: [],
        any_installed_keg:                      instance_double(Keg, tab: tab_from_keg),
      )
    end
  end

  describe "::bottled_formulae_with_no_formula_dependents" do
    include_context "with formulae for dependency testing"

    before do
      allow(Formulary).to receive(:factory).with("three", { warn: false })
                                           .and_return(formula_is_build_dep)
    end

    context "when formulae are bottles" do
      it "filters out runtime dependencies" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)

        expect(described_class.send(:bottled_formulae_with_no_formula_dependents, formulae))
          .to eq([formula_with_deps, formula_is_build_dep])
      end
    end

    context "when formulae are built from source" do
      it "filters out formulae" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(false)

        expect(described_class.send(:bottled_formulae_with_no_formula_dependents, formulae))
          .to eq([])
      end
    end
  end

  describe "::unused_formulae_with_no_formula_dependents" do
    include_context "with formulae for dependency testing"

    before do
      allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)
    end

    specify "installed on request" do
      allow(tab_from_keg).to receive_messages(installed_on_request: true, installed_on_request_present?: true)

      expect(described_class.send(:unused_formulae_with_no_formula_dependents, formulae))
        .to eq([])
    end

    specify "not installed on request" do
      allow(tab_from_keg).to receive_messages(installed_on_request: false, installed_on_request_present?: true)

      expect(described_class.send(:unused_formulae_with_no_formula_dependents, formulae))
        .to match_array(formulae)
    end

    specify "installed on request is null" do
      allow(tab_from_keg).to receive_messages(installed_on_request: false, installed_on_request_present?: false)

      expect(described_class.send(:unused_formulae_with_no_formula_dependents, formulae))
        .to eq([])
    end
  end

  shared_context "with formulae and casks for dependency testing" do
    include_context "with formulae for dependency testing"

    require "cask/cask_loader"

    let(:cask_one_dep) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "red" do
          depends_on formula: "two"
        end
      RUBY
    end

    let(:cask_multiple_deps) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "blue" do
          depends_on formula: "zero"
        end
      RUBY
    end

    let(:first_cask_no_deps) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "green" do
        end
      RUBY
    end

    let(:second_cask_no_deps) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "purple" do
        end
      RUBY
    end

    let(:casks_no_deps) { [first_cask_no_deps, second_cask_no_deps] }
    let(:casks_one_dep) { [first_cask_no_deps, second_cask_no_deps, cask_one_dep] }
    let(:casks_multiple_deps) { [first_cask_no_deps, second_cask_no_deps, cask_multiple_deps] }

    before do
      allow(Formulary).to receive(:resolve).with("zero").and_return(formula_with_deps)
      allow(Formulary).to receive(:resolve).with("one").and_return(first_formula_dep)
      allow(Formulary).to receive(:resolve).with("two").and_return(second_formula_dep)
    end
  end

  describe "::formulae_with_cask_dependents" do
    include_context "with formulae and casks for dependency testing"

    specify "no dependents" do
      expect(described_class.send(:formulae_with_cask_dependents, casks_no_deps))
        .to eq([])
    end

    specify "one dependent" do
      expect(described_class.send(:formulae_with_cask_dependents, casks_one_dep))
        .to eq([second_formula_dep])
    end

    specify "multiple dependents" do
      expect(described_class.send(:formulae_with_cask_dependents, casks_multiple_deps))
        .to contain_exactly(formula_with_deps, first_formula_dep, second_formula_dep)
    end
  end
end
