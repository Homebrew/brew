# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::Formulae do
  describe "#testing_portable_ruby?" do
    it "returns false (not nil) when tap is nil" do
      # Regression test: without `!!`, tap&.core_tap? returns nil when tap is nil,
      # and `nil && ...` evaluates to nil, violating the T::Boolean return type.
      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )

        result = formulae.send(:testing_portable_ruby?)
        expect(result).to be(false)
      end
    end
  end

  describe "#verify_local_bottles" do
    it "returns false (not nil) when testing portable ruby" do
      # Regression test: the early return for portable ruby must be `return false`,
      # not bare `return` (which returns nil), to satisfy the T::Boolean return type.
      Dir.mktmpdir do |tmpdir|
        output_paths = {
          bottle:                     Pathname.new("#{tmpdir}/bottle.txt"),
          linkage:                    Pathname.new("#{tmpdir}/linkage.txt"),
          skipped_or_failed_formulae: Pathname.new("#{tmpdir}/skipped.txt"),
        }
        formulae = described_class.new(
          tap: CoreTap.instance, git: "git", dry_run: true, fail_fast: false, verbose: false,
          output_paths:
        )
        formulae.testing_formulae = ["portable-ruby"]

        result = formulae.send(:verify_local_bottles)
        expect(result).to be(false)
      end
    end
  end
end
