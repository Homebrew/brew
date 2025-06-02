# frozen_string_literal: true

RSpec.describe Cask::Artifact::PreflightBlock, :cask do
  describe "install_phase" do
    it "calls the specified block before installing, passing a Cask mini-dsl" do
      called = false
      yielded_arg = nil

      cask = Cask::Cask.new("with-preflight") do
        preflight do |c|
          called = true
          yielded_arg = c
        end
      end

      cask.artifacts.select { |a| a.is_a?(described_class) }.each do |artifact|
        artifact.install_phase(command: NeverSudoSystemCommand, force: false)
      end

      expect(called).to be true
      expect(yielded_arg).to be_a Cask::DSL::Preflight
    end
  end

  describe "uninstall_phase" do
    it "calls the specified block before uninstalling, passing a Cask mini-dsl" do
      called = false
      yielded_arg = nil

      cask = Cask::Cask.new("with-uninstall-preflight") do
        uninstall_preflight do |c|
          called = true
          yielded_arg = c
        end
      end

      cask.artifacts.select { |a| a.is_a?(described_class) }.each do |artifact|
        artifact.uninstall_phase(command: NeverSudoSystemCommand, force: false)
      end

      expect(called).to be true
      expect(yielded_arg).to be_a Cask::DSL::UninstallPreflight
    end
  end
end
