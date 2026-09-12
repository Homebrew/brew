# typed: strict
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  describe "#check_brew_path" do
    sig { returns(Homebrew::Diagnostic::Checks) }
    subject(:checks) { described_class.new }

    sig { returns(Pathname) }
    def brew
      HOMEBREW_PREFIX/"bin/brew"
    end

    sig { returns(Pathname) }
    def other_brew
      HOMEBREW_TEMP/"wrapper/bin/brew"
    end

    before do
      brew.dirname.mkpath
      brew.write("#!/bin/sh\n")
      brew.chmod 0755
      other_brew.dirname.mkpath
      other_brew.write("#!/bin/sh\nexit 1\n")
      other_brew.chmod 0755
      stub_const("HOMEBREW_BREW_FILE", brew)
      stub_const("ORIGINAL_PATHS", [other_brew.dirname, brew.dirname])
    end

    it "warns when another brew shadows this installation" do
      expect(checks.check_brew_path&.to_s)
        .to include("Another `brew` shadows this Homebrew installation in your PATH:",
                    other_brew.to_s, "#{HOMEBREW_PREFIX}/bin")
    end

    it "checks the original PATH, not Homebrew's modified PATH" do
      ENV["PATH"] = brew.dirname.to_s

      expect(checks.check_brew_path).not_to be_nil
    end

    it "uses the same PATH guidance as the missing-bin warning" do
      stub_const("ORIGINAL_PATHS", [other_brew.dirname])

      expect(checks.check_brew_path&.remediation&.to_h)
        .to eq(checks.check_user_path_2&.remediation&.to_h)
    end

    it "does not warn when this installation takes precedence" do
      stub_const("ORIGINAL_PATHS", [brew.dirname, other_brew.dirname])

      expect(checks.check_brew_path).to be_nil
    end

    it "does not warn about symlinks to the same brew" do
      other_brew.unlink
      FileUtils.ln_s brew, other_brew

      expect(checks.check_brew_path).to be_nil
    end

    it "ignores non-executable files" do
      other_brew.chmod 0644

      expect(checks.check_brew_path).to be_nil
    end

    it "ignores directories named brew" do
      other_brew.unlink
      other_brew.mkpath

      expect(checks.check_brew_path).to be_nil
    end

    it "does not duplicate the missing PATH warning" do
      stub_const("ORIGINAL_PATHS", [])

      expect(checks.check_brew_path).to be_nil
    end
  end
end
