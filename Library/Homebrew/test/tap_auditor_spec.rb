# frozen_string_literal: true

require "tap_auditor"

RSpec.describe Homebrew::TapAuditor do
  subject(:tap_auditor) { described_class.new(tap) }

  let(:tap) { Tap.fetch("user", "repo") }
  let(:ruby_files) { [] }

  before do
    tap.path.mkpath

    ruby_files.each do |ruby_file|
      ruby_file.dirname.mkpath
      FileUtils.touch ruby_file
    end
  end

  after do
    tap.path.dirname.rmtree
  end

  context "when Ruby files are in a wrong location" do
    let(:ruby_files) do
      [
        tap.path/"wrong"/"file.rb",
      ]
    end

    it "fails" do
      tap_auditor.audit
      expect(tap_auditor.problems.first[:message]).to match "Ruby files in wrong location"
    end
  end

  context "when formula files are in homebrew/cask" do
    let(:tap) { CoreCaskTap.instance }
    let(:ruby_files) do
      [
        tap.path/"Formula"/"formula.rb",
      ]
    end

    it "fails" do
      tap_auditor.audit
      expect(tap_auditor.problems.first[:message]).to match "Ruby files in wrong location"
    end
  end

  context "when cask files are in homebrew/core" do
    let(:tap) { CoreTap.instance }
    let(:ruby_files) do
      [
        tap.path/"Casks"/"cask.rb",
      ]
    end

    it "fails" do
      tap_auditor.audit
      expect(tap_auditor.problems.first[:message]).to match "Ruby files in wrong location"
    end
  end

  context "when Ruby files are in correct locations" do
    let(:ruby_files) do
      [
        tap.path/"cmd"/"cmd.rb",
        tap.path/"Formula"/"formula.rb",
        tap.path/"Casks"/"cask.rb",
      ]
    end

    it "passes" do
      tap_auditor.audit
      expect(tap_auditor.problems).to be_empty
    end
  end
end
