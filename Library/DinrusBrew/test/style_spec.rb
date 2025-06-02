# frozen_string_literal: true

require "style"

RSpec.describe DinrusBrew::Style do
  around do |example|
    FileUtils.ln_s DINRUSBREW_LIBRARY_PATH, DINRUSBREW_LIBRARY/"DinrusBrew"
    FileUtils.ln_s DINRUSBREW_LIBRARY_PATH.parent/".rubocop.yml", DINRUSBREW_LIBRARY/".rubocop.yml"

    example.run
  ensure
    FileUtils.rm_f DINRUSBREW_LIBRARY/"DinrusBrew"
    FileUtils.rm_f DINRUSBREW_LIBRARY/".rubocop.yml"
  end

  before do
    allow(DinrusBrew).to receive(:install_bundler_gems!)
  end

  describe ".check_style_json" do
    let(:dir) { mktmpdir }

    it "returns offenses when RuboCop reports offenses" do
      formula = dir/"my-formula.rb"

      formula.write <<~EOS
        class MyFormula < Formula

        end
      EOS

      style_offenses = described_class.check_style_json([formula])

      expect(style_offenses.for_path(formula.realpath).map(&:message))
        .to include("Extra empty line detected at class body beginning.")
    end
  end

  describe ".check_style_and_print" do
    let(:dir) { mktmpdir }

    it "returns true (success) for conforming file with only audit-level violations" do
      # This file is known to use non-rocket hashes and other things that trigger audit,
      # but not regular, cop violations
      target_file = DINRUSBREW_LIBRARY_PATH/"utils.rb"

      style_result = described_class.check_style_and_print([target_file])

      expect(style_result).to be true
    end
  end
end
