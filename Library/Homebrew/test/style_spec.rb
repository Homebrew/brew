# typed: true
# frozen_string_literal: true

require "style"

RSpec.describe Homebrew::Style do
  around do |example|
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH, HOMEBREW_LIBRARY/"Homebrew"
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH.parent/".rubocop.yml", HOMEBREW_LIBRARY/".rubocop.yml"

    example.run
  ensure
    FileUtils.rm_f HOMEBREW_LIBRARY/"Homebrew"
    FileUtils.rm_f HOMEBREW_LIBRARY/".rubocop.yml"
  end

  before do
    allow(Homebrew).to receive(:install_bundler_gems!)
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
      target_file = HOMEBREW_LIBRARY_PATH/"utils.rb"

      style_result = described_class.check_style_and_print([target_file])

      expect(style_result).to be true
    end
  end

  describe ".run_rubocop" do
    let(:dir) { mktmpdir }
    let(:ruby_file) { dir/"test.rb" }

    before do
      ruby_file.write <<~RUBY
        class Test
        end
      RUBY
    end

    it "passes --disable-uncorrectable when --todo is enabled" do
      result = double(status: double(exitstatus: 0), stdout: '{"files":[]}')

      expect(described_class).to receive(:system_command) do |_cmd, args:, **|
        expect(args).to include("--disable-uncorrectable")
        result
      end

      described_class.run_rubocop([ruby_file], :json, fix: true, todo: true)
    end
  end
end
