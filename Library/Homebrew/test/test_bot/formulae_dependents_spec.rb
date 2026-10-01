# typed: true
# frozen_string_literal: true

require "dev-cmd/test-bot"
require "test_bot"

RSpec.describe Homebrew::TestBot::FormulaeDependents do
  subject(:formulae_dependents) do
    described_class.new(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
  end

  describe "#dependents_for_shard" do
    it "keeps dependent formulae that depend on each other in the same shard" do
      dependency = formula "dependent-a" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-a-1.0.tar.gz"
      end
      dependent = formula "dependent-b" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-b-1.0.tar.gz"
        depends_on "dependent-a"
      end
      independent = formula "dependent-c" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-c-1.0.tar.gz"
      end

      stub_formula_loader dependency
      stub_formula_loader dependent
      stub_formula_loader independent

      shard = formulae_dependents.dependents_for_shard(
        [
          [dependency, dependency.deps.to_a],
          [dependent, dependent.deps.to_a],
          [independent, independent.deps.to_a],
        ],
        "1/2",
      )

      expect(shard.map { |formula, _| formula.name }).to contain_exactly("dependent-a", "dependent-b")
    end

    it "rejects invalid shard indexes" do
      expect { formulae_dependents.dependents_for_shard([], "2/1") }
        .to raise_error(UsageError, /must not be greater/)
    end

    it "returns no formulae for an empty shard" do
      dependent = formula "dependent-a" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-a-1.0.tar.gz"
      end

      expect(formulae_dependents.dependents_for_shard([[dependent, dependent.deps.to_a]], "2/2")).to be_empty
    end
  end

  describe "#install_formulae_if_needed_from_bottles!" do
    subject(:formulae_dependents) do
      Class.new(described_class) do
        T.bind(self, T.class_of(Homebrew::TestBot::FormulaeDependents))
        public :install_formulae_if_needed_from_bottles!
      end.new(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
    end

    let(:args) { Homebrew::Cmd::TestBotCmd.new([]).args }

    before do
      allow(Utils::Bottles).to receive(:tag).and_return(Utils::Bottles::Tag.from_symbol(:arm64_linux))

      intel_only = formula "intel-only" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/intel-only-1.0.tar.gz"
        depends_on arch: :x86_64
      end
      portable = formula "portable" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/portable-1.0.tar.gz"
      end

      stub_formula_loader intel_only, call_original: true
      stub_formula_loader portable
    end

    it "installs bottles for formulae this runner can build" do
      expect(formulae_dependents).to receive(:install_formula_from_bottle!)
        .with("portable", testing_formulae_dependents: true, dry_run: false)

      formulae_dependents.install_formulae_if_needed_from_bottles!(["portable"], args:)
    end

    it "skips bottles for formulae this runner cannot build" do
      expect(formulae_dependents).not_to receive(:install_formula_from_bottle!)

      formulae_dependents.install_formulae_if_needed_from_bottles!(["intel-only"], args:)
    end

    it "warns about formulae that cannot be loaded" do
      expect { formulae_dependents.install_formulae_if_needed_from_bottles!(["unavailable"], args:) }
        .to output(/No available formula with the name "unavailable"/).to_stderr
    end

    it "installs bottles after formulae that cannot be loaded" do
      allow(formulae_dependents).to receive(:opoo)

      expect(formulae_dependents).to receive(:install_formula_from_bottle!)
        .with("portable", testing_formulae_dependents: true, dry_run: false)

      formulae_dependents.install_formulae_if_needed_from_bottles!(["unavailable", "portable"], args:)
    end
  end

  describe "#split_source_dependents" do
    let(:dependents) { dependents_hash.values }
    let(:dependents_hash) do
      14.downto(6).to_h do |i|
        f = formula "dependent-#{i}" do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/dependent-#{i}/1.0.tar.gz"
          depends_on "dependency"
        end
        [i, [f, f.deps.to_a]]
      end
    end

    before do
      stub_formula_loader(
        formula("dependency") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/dependency/1.0.tar.gz"
        end,
      )
      allow(Homebrew::API::Analytics).to receive(:fetch).with("install", 90).and_return({
        "items" => 1.upto(20).map { |i| { "number" => i, "formula" => "dependent-#{i}" } },
      })
      allow(formulae_dependents).to receive_messages(
        build_dependent_from_source?: true,
        bottled_or_built?:            true,
      )
    end

    it "does not source build dependents with unbottled dependency" do
      unbottled_dependency = formula "unbottled-dependency" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/unbottled-dependency/1.0.tar.gz"
        depends_on "dependency"
      end
      stub_formula_loader unbottled_dependency
      allow(formulae_dependents).to receive(:bottled_or_built?).with(unbottled_dependency, []).and_return(false)

      source_dependents = dependents_hash.values
      dependent_with_unbottled_dep = formula "dependent-5" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-5/1.0.tar.gz"
        depends_on "dependency"
        depends_on "unbottled-dependency"
      end
      not_source_dependent = [dependent_with_unbottled_dep, dependent_with_unbottled_dep.deps.to_a]
      dependents_hash[5] = not_source_dependent

      expect(formulae_dependents.split_source_dependents(dependents)).to eq [
        source_dependents,
        [not_source_dependent],
      ]
    end

    it "limits total source build dependents to upper bound and orders on analytics" do
      expect(formulae_dependents.split_source_dependents(dependents, 1)).to eq [
        [dependents_hash.fetch(6)],
        7.upto(14).map { dependents_hash.fetch(it) },
      ]
      expect(formulae_dependents.split_source_dependents(dependents, 5)).to eq [
        6.upto(10).map { dependents_hash.fetch(it) },
        11.upto(14).map { dependents_hash.fetch(it) },
      ]
      expect(formulae_dependents.split_source_dependents(dependents, 7)).to eq [
        6.upto(12).map { dependents_hash.fetch(it) },
        13.upto(14).map { dependents_hash.fetch(it) },
      ]
    end
  end
end
