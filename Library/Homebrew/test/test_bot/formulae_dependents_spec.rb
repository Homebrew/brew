# typed: true
# frozen_string_literal: true

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

      shard = formulae_dependents.send(
        :dependents_for_shard,
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
      expect { formulae_dependents.send(:dependents_for_shard, [], "2/1") }
        .to raise_error(UsageError, /must not be greater/)
    end

    it "returns no formulae for an empty shard" do
      dependent = formula "dependent-a" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-a-1.0.tar.gz"
      end

      expect(formulae_dependents.send(:dependents_for_shard, [[dependent, dependent.deps.to_a]], "2/2")).to be_empty
    end
  end
end
