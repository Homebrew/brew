# typed: true
# frozen_string_literal: true

require "yaml"
require "rubocops/unreferenced_let"

RSpec.describe RuboCop::Cop::Homebrew::UnreferencedLet, :config do
  # `RSpec::Base#on_new_investigation` reads `config["RSpec"]["Language"]` to drive the RSpec DSL
  # matchers (`shared_group?`, `include?`). A full `brew style` run merges that from rubocop-rspec's
  # plugin config, but the isolated cop spec does not, so supply it from the gem's `default.yml`.
  let(:other_cops) do
    language_matcher_source, = RuboCop::RSpec::Language.instance_method(:include?).source_location
    language = YAML.safe_load_file(
      File.expand_path("../../../../config/default.yml", language_matcher_source),
      permitted_classes: [Regexp, Symbol], aliases: true,
    ).fetch("RSpec").fetch("Language")
    { "RSpec" => { "Language" => language } }
  end

  it "flags and removes unreferenced lazy lets" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:unused) { create(:thing) }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.
        let(:also_unused) { create(:other) }
        ^^^ Remove unreferenced `let(:also_unused)` -- its name is never used, so the block never runs.

        it { expect(1).to eq(1) }
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do

        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "removes a preceding Sorbet signature along with the let" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        sig { returns(Integer) }
        let(:unused) { 1 }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        it { expect(1).to eq(1) }
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "flags an unreferenced let written as a numbered-parameter block" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:unused) { create(_1) }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
      end
    RUBY
  end

  it "removes an explanatory comment attached directly above the let" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:kept) { 1 }

        # allows us to see the output
        let(:unused) { false }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        it { expect(kept).to eq(1) }
      end
    RUBY

    # The comment + let are removed, and the now-duplicate trailing blank is consumed so no
    # stray blank is left behind.
    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        let(:kept) { 1 }

        it { expect(kept).to eq(1) }
      end
    RUBY
  end

  it "consumes a trailing blank at a block-body edge but keeps the blank after a final let" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:kept) { 1 }
        let(:unused) { 2 }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        it { expect(kept).to eq(1) }
      end
    RUBY

    # `let(:kept)` precedes the removal, so the blank after it (the final-let separator) stays.
    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        let(:kept) { 1 }

        it { expect(kept).to eq(1) }
      end
    RUBY
  end

  it "does not absorb a rubocop directive comment above the let" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        # rubocop:disable Style/Something
        let(:unused) { false }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.
        # rubocop:enable Style/Something
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        # rubocop:disable Style/Something
        # rubocop:enable Style/Something
      end
    RUBY
  end

  it "does not flag an eager let! (out of scope)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let!(:unused) { create(:thing) }

        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "does not flag a referenced lazy let" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:thing) { create(:thing) }

        it { expect(thing).to be_present }
      end
    RUBY
  end

  it "does not flag `let(:cop_config)` (a rubocop-rspec framework contract)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe RuboCop::Cop::Homebrew::SomeCop, :config do
        let(:cop_config) { { "Enabled" => true } }

        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "does not flag a let referenced via dynamic dispatch" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:thing) { create(:thing) }

        it { expect(send(:thing)).to be_present }
      end
    RUBY
  end

  it "does not flag a let referenced only as a symbol literal (data-table dispatch)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:special_formula) { build(:formula) }

        it "dispatches by name" do
          [[:special_formula, :pending]].each do |name, _state|
            expect(send(name)).to be_present
          end
        end
      end
    RUBY
  end

  it "does not flag a let referenced only as a string literal (string dispatch)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:special_formula) { build(:formula) }

        it { expect(send("special_formula")).to be_present }
      end
    RUBY
  end

  it "does not flag a let referenced only inside a heredoc body" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:cutoff_date) { Date.today }
        let(:query) do
          <<~SQL
            SELECT * FROM things WHERE created_at < cutoff_date
          SQL
        end

        it { expect(described_class.run(query)).to be_present }
      end
    RUBY
  end

  it "skips every let in a file that dispatches through an interpolated string" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:expected_dental_value) { 1 }

        it "dispatches by interpolated name" do
          %w[dental vision].each do |type|
            expect(described_class.for(type)).to eq(send("expected_\#{type}_value"))
          end
        end
      end
    RUBY
  end

  it "still flags a dead let in a file whose only send target is a static string" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:unused) { create(:thing) }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        it { expect(send("other")).to be_present }
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        it { expect(send("other")).to be_present }
      end
    RUBY
  end

  it "does not crash on a let whose block contains an invalid-UTF-8 string literal" do
    expect_offense(<<~'RUBY')
      RSpec.describe Thing do
        let(:unused) { String.new("\xc2invalid", encoding: "UTF-8") }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        it { expect(1).to eq(1) }
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "does not flag a name defined by more than one let/let! (override / super chain)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:value) { 1 }

        context "nested" do
          let!(:value) { 2 }

          it { expect(1).to eq(1) }
        end
      end
    RUBY
  end

  it "does not flag a let overridden by a subject of the same name (super chain)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:described) { build(:thing) }

        context "when active" do
          subject(:described) { super().tap(&:activate) }

          it { is_expected.to be_active }
        end
      end
    RUBY
  end

  it "does not flag an unreferenced subject (only lazy let is in scope)" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        subject(:unused) { build(:thing) }

        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "skips every let in a file that consumes shared examples" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:unused) { create(:thing) }

        it_behaves_like "a thing"
      end
    RUBY
  end

  it "skips a let declared inside a shared example definition" do
    expect_no_offenses(<<~RUBY)
      RSpec.shared_examples "a thing" do
        let(:unused_inner) { create(:thing) }

        it { expect(1).to eq(1) }
      end
    RUBY
  end

  it "still flags an unreferenced let declared outside a shared example definition" do
    expect_offense(<<~RUBY)
      RSpec.describe Thing do
        let(:unused) { create(:thing) }
        ^^^ Remove unreferenced `let(:unused)` -- its name is never used, so the block never runs.

        shared_examples "a thing" do
          it { expect(1).to eq(1) }
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      RSpec.describe Thing do
        shared_examples "a thing" do
          it { expect(1).to eq(1) }
        end
      end
    RUBY
  end

  it "ignores let declarations without a symbol name" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        name = :dynamic
        let(name) { create(:thing) }
        let { create(:thing) }
      end
    RUBY
  end

  it "ignores a let call with no block" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        let(:unused)
      end
    RUBY
  end

  it "ignores a let-like call with an explicit receiver" do
    expect_no_offenses(<<~RUBY)
      RSpec.describe Thing do
        config.let(:unused) { create(:thing) }
      end
    RUBY
  end
end
