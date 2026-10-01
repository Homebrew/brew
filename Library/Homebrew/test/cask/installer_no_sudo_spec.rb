# typed: strict
# frozen_string_literal: true

require "cask/installer"

RSpec.describe Cask::Installer, :cask do
  it "rejects pkg casks during requirements checks when sudo is disabled" do
    ENV["HOMEBREW_NO_SUDO"] = "1"
    cask = Cask::CaskLoader.load(cask_path("with-installable"))

    expect { described_class.new(cask).check_requirements }
      .to raise_error(Cask::CaskError, /pkg artifact requires sudo/)
  end

  it "preserves pkg casks when sudo is enabled" do
    ENV.delete("HOMEBREW_NO_SUDO")
    cask = Cask::CaskLoader.load(cask_path("with-installable"))

    expect { described_class.new(cask).check_requirements }.not_to raise_error
  end

  it "rejects installer scripts that require sudo before installation" do
    ENV["HOMEBREW_NO_SUDO"] = "1"
    cask = Cask::CaskLoader.load(cask_path("with-installable"))
    allow(cask).to receive(:artifacts).and_return(Set[Cask::Artifact::Installer.new(cask, script: {
      executable: "install.sh", sudo: true
    })])

    expect { described_class.new(cask).check_requirements }
      .to raise_error(Cask::CaskError, /installer artifact requires sudo/)
  end

  it "allows installer scripts that do not require sudo" do
    ENV["HOMEBREW_NO_SUDO"] = "1"
    cask = Cask::CaskLoader.load(cask_path("with-installable"))
    allow(cask).to receive(:artifacts).and_return(Set[Cask::Artifact::Installer.new(cask, script: "install.sh")])

    expect { described_class.new(cask).check_requirements }.not_to raise_error
  end

  context "when sudo is disabled" do
    sig { returns(Cask::Cask) }
    let(:cask) { Cask::CaskLoader.load(cask_path("with-installable")) }

    before { ENV["HOMEBREW_NO_SUDO"] = "1" }

    it "rejects keyboard layouts during requirements checks" do
      allow(cask).to receive(:artifacts).and_return(Set[Cask::Artifact::KeyboardLayout.new(cask, "Example.bundle")])

      expect { described_class.new(cask).check_requirements }
        .to raise_error(Cask::CaskError, /keyboard_layout artifact requires sudo/)
    end

    test_each([Cask::Artifact::PreflightSteps, Cask::Artifact::PostflightSteps]) do |artifact_class|
      it "rejects privileged #{artifact_class.dsl_key} during requirements checks" do
        steps = Homebrew::InstallSteps::DSL.build do
          run "/usr/bin/true", sudo: true
        end
        allow(cask).to receive(:artifacts).and_return(Set[artifact_class.new(cask, steps)])

        expect { described_class.new(cask).check_requirements }
          .to raise_error(Cask::CaskError, /#{artifact_class.dsl_key} artifact requires sudo/)
      end
    end

    it "rejects steps with implicit sudo requirements" do
      steps = Homebrew::InstallSteps::DSL.build do
        delete_keychain_certificates "Example"
      end
      allow(cask).to receive(:artifacts).and_return(Set[Cask::Artifact::PostflightSteps.new(cask, steps)])

      expect { described_class.new(cask).check_requirements }
        .to raise_error(Cask::CaskError, /postflight_steps artifact requires sudo/)
    end

    it "allows install steps that can run without elevation" do
      steps = Homebrew::InstallSteps::DSL.build do
        run "/usr/bin/true"
        set_ownership "/Applications/Example.app"
        remove "/Applications/Example.app", sudo: :if_needed
        symlink "/Applications/Example.app", "/tmp/example", sudo: :if_needed
      end
      allow(cask).to receive(:artifacts).and_return(Set[Cask::Artifact::PostflightSteps.new(cask, steps)])

      expect { described_class.new(cask).check_requirements }.not_to raise_error
    end

    test_each([Cask::Artifact::UninstallPreflightSteps, Cask::Artifact::UninstallPostflightSteps]) do |artifact_class|
      it "allows privileged #{artifact_class.dsl_key} during installation" do
        steps = Homebrew::InstallSteps::DSL.build do
          run "/usr/bin/true", sudo: true
        end
        allow(cask).to receive(:artifacts).and_return(Set[artifact_class.new(cask, steps)])

        expect { described_class.new(cask).check_requirements }.not_to raise_error
      end
    end
  end
end
