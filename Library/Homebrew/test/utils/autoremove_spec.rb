# typed: true
# frozen_string_literal: true

require "utils/autoremove"

RSpec.describe Utils::Autoremove do
  shared_context "with formulae for dependency testing" do
    let(:formula_with_deps) do
      formula "zero" do
        T.bind(self, T.class_of(Formula))
        url "zero-1.0"

        depends_on "three" => :build
      end
    end

    let(:first_formula_dep) do
      formula "one" do
        T.bind(self, T.class_of(Formula))
        url "one-1.1"
      end
    end

    let(:second_formula_dep) do
      formula "two" do
        T.bind(self, T.class_of(Formula))
        url "two-1.1"
      end
    end

    let(:formula_is_build_dep) do
      formula "three" do
        T.bind(self, T.class_of(Formula))
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
      allow(tab_from_keg).to receive(:runtime_dependencies).and_return(nil)
      allow(formula_with_deps).to receive_messages(
        installed_runtime_formula_dependencies: [first_formula_dep, second_formula_dep],
        any_installed_keg:                      instance_double(Keg, tab: tab_from_keg),
        bottled?:                               true,
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

  describe "::formulae_with_no_formula_dependents" do
    include_context "with formulae for dependency testing"

    before do
      allow(Formulary).to receive(:factory).with("three", { warn: false })
                                           .and_return(formula_is_build_dep)
    end

    context "when formulae are bottles" do
      it "filters out runtime dependencies" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps, formula_is_build_dep])
      end

      it "filters out build dependencies when there is no longer a usable bottle" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)
        allow(formula_with_deps).to receive(:bottled?).and_return(false)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps])
      end

      it "filters out build dependencies when the bottle can't be poured" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)
        allow(formula_with_deps).to receive(:pour_bottle?).and_return(false)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps])
      end
    end

    context "when formulae are built from source" do
      it "filters out runtime and build dependencies" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(false)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps])
      end
    end

    context "when tab has runtime_dependencies data" do
      it "uses tab dep names without calling installed_runtime_formula_dependencies" do
        allow(tab_from_keg).to receive_messages(
          runtime_dependencies: [{ "full_name" => "one" }, { "full_name" => "two" }], poured_from_bottle: true,
        )

        expect(formula_with_deps).not_to receive(:installed_runtime_formula_dependencies)
        expect(first_formula_dep).not_to receive(:installed_runtime_formula_dependencies)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps, formula_is_build_dep])
      end

      it "matches runtime dependencies by any of the formula's names" do
        allow(tab_from_keg).to receive_messages(
          runtime_dependencies: [{ "full_name" => "old-one" }], poured_from_bottle: true,
        )
        allow(first_formula_dep).to receive(:possible_names).and_return(["one", "old-one"])

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps, second_formula_dep, formula_is_build_dep])
      end
    end

    context "when there is no receipt" do
      it "filters out build dependencies" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(true)
        allow(formula_with_deps).to receive(:any_installed_keg).and_return(nil)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps])
      end
    end

    context "when a build dependency loads as a different object" do
      it "matches it by name" do
        allow(tab_from_keg).to receive(:poured_from_bottle).and_return(false)
        different_object = formula "three" do
          T.bind(self, T.class_of(Formula))
          url "three-1.1"
        end
        allow(Formulary).to receive(:factory).with("three", { warn: false }).and_return(different_object)

        expect(described_class.formulae_with_no_formula_dependents(formulae))
          .to eq([formula_with_deps])
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

      expect(described_class.unused_formulae_with_no_formula_dependents(formulae))
        .to eq([])
    end

    specify "not installed on request" do
      allow(tab_from_keg).to receive_messages(installed_on_request: false, installed_on_request_present?: true)

      expect(described_class.unused_formulae_with_no_formula_dependents(formulae))
        .to match_array(formulae)
    end

    specify "installed on request is null" do
      allow(tab_from_keg).to receive_messages(installed_on_request: false, installed_on_request_present?: false)

      expect(described_class.unused_formulae_with_no_formula_dependents(formulae))
        .to eq([])
    end

    specify "built from source and not installed on request" do
      allow(Formulary).to receive(:factory).with("three", { warn: false }).and_return(formula_is_build_dep)
      allow(tab_from_keg).to receive_messages(poured_from_bottle:            false,
                                              installed_on_request:          false,
                                              installed_on_request_present?: true)

      expect(described_class.unused_formulae_with_no_formula_dependents(formulae))
        .to match_array(formulae)
    end
  end

  describe "::formulae_safe_to_remove" do
    include_context "with formulae for dependency testing"

    before do
      allow(Formulary).to receive(:factory).with("three", { warn: false }).and_return(formula_is_build_dep)
      allow(tab_from_keg).to receive(:poured_from_bottle).and_return(false)
    end

    it "removes formulae when everything that depends on them is also being removed" do
      expect(described_class.formulae_safe_to_remove(formulae, formulae))
        .to match_array(formulae)
    end

    it "keeps runtime and build dependencies of formulae that stay installed" do
      expect(described_class.formulae_safe_to_remove(formulae - [formula_with_deps], formulae))
        .to eq([])
    end

    it "keeps dependencies of formulae that it has decided to keep" do
      allow(formula_with_deps).to receive(:installed_runtime_formula_dependencies).and_return([first_formula_dep])

      expect(described_class.formulae_safe_to_remove([first_formula_dep, second_formula_dep], formulae))
        .to eq([])
    end
  end

  shared_context "with formulae and casks for dependency testing" do
    include_context "with formulae for dependency testing"

    require "cask/cask_loader"

    let(:cask_one_dep) do
      Cask::CaskLoader.from_content(+<<-RUBY)
        cask "red" do
          depends_on formula: "two"
        end
      RUBY
    end

    let(:cask_multiple_deps) do
      Cask::CaskLoader.from_content(+<<-RUBY)
        cask "blue" do
          depends_on formula: "zero"
        end
      RUBY
    end

    let(:first_cask_no_deps) do
      Cask::CaskLoader.from_content(+<<-RUBY)
        cask "green" do
        end
      RUBY
    end

    let(:second_cask_no_deps) do
      Cask::CaskLoader.from_content(+<<-RUBY)
        cask "purple" do
        end
      RUBY
    end

    let(:casks_no_deps) { [first_cask_no_deps, second_cask_no_deps] }
    let(:casks_one_dep) { [first_cask_no_deps, second_cask_no_deps, cask_one_dep] }
    let(:casks_multiple_deps) { [first_cask_no_deps, second_cask_no_deps, cask_multiple_deps] }
  end

  describe "::cask_dependent_formula_names" do
    include_context "with formulae and casks for dependency testing"

    specify "no dependents" do
      expect(described_class.cask_dependent_formula_names(casks_no_deps, formulae))
        .to eq(Set.new)
    end

    specify "one dependent" do
      expect(described_class.cask_dependent_formula_names(casks_one_dep, formulae))
        .to contain_exactly("two")
    end

    specify "multiple dependents" do
      expect(described_class.cask_dependent_formula_names(casks_multiple_deps, formulae))
        .to contain_exactly("zero", "one", "two")
    end
  end
end
