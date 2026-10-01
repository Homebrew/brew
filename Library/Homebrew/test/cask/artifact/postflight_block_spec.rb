# typed: strict
# frozen_string_literal: true

RSpec.describe Cask::Artifact::PostflightBlock, :cask do
  before do
    ENV["HOMEBREW_DEVELOPER"] = nil
    Homebrew.raise_deprecation_exceptions = false
  end

  describe "install_phase" do
    it "calls the specified block after installing, passing a Cask mini-dsl" do
      called = T.let(false, T::Boolean)
      yielded_arg = T.let(nil, T.nilable(Cask::DSL::Postflight))

      cask = Cask::Cask.new("with-postflight") do
        postflight do |c|
          called = true
          yielded_arg = c
        end
      end

      cask.artifacts.grep(described_class).each do |artifact|
        artifact.install_phase(command: NeverSudoSystemCommand, force: false)
      end

      expect(called).to be true
      expect(yielded_arg).to be_a(Cask::DSL::Postflight)
    end
  end

  describe "uninstall_phase" do
    it "accepts an empty block loaded from the API" do
      cask = Cask::Cask.new("with-uninstall-postflight")
      artifact = described_class.new(cask, uninstall_postflight: Homebrew::API::CaskStruct::EMPTY_BLOCK)

      expect { artifact.uninstall_phase(command: NeverSudoSystemCommand, force: false) }.not_to raise_error
    end

    it "calls the specified block after uninstalling, passing a Cask mini-dsl" do
      called = T.let(false, T::Boolean)
      yielded_arg = T.let(nil, T.nilable(Cask::DSL::UninstallPostflight))

      cask = Cask::Cask.new("with-uninstall-postflight") do
        uninstall_postflight do |c|
          called = true
          yielded_arg = c
        end
      end

      cask.artifacts.grep(described_class).each do |artifact|
        artifact.uninstall_phase(command: NeverSudoSystemCommand, force: false)
      end

      expect(called).to be true
      expect(yielded_arg).to be_a(Cask::DSL::UninstallPostflight)
    end
  end
end
