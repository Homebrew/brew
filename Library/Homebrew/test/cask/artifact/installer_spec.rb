# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::Installer, :cask do
  subject(:installer) { described_class.new(cask, **args) }

  let(:staged_path) { mktmpdir }
  let(:cask) { instance_double(Cask::Cask, staged_path:) }
  let(:command) { SystemCommand }
  let(:args) { {} }

  describe "#initialize" do
    context "when given a manual installer that is not a path" do
      let(:args) { { manual: 123 } }

      it "raises an error" do
        expect { installer }.to raise_error(Cask::CaskInvalidError, /requires a path for :manual/)
      end
    end
  end

  describe "#install_phase" do
    context "when given a manual installer" do
      let(:args) { { manual: "installer" } }

      it "shows a message prompting to run the installer manually" do
        expect do
          installer.install_phase(command:)
        end.to output(%r{open #{staged_path}/installer}).to_stdout
      end
    end

    context "when given a script installer" do
      let(:executable) { staged_path/"executable" }
      let(:args) { { script: { executable: "executable" } } }

      before do
        FileUtils.touch executable
      end

      it "looks for the executable in HOMEBREW_PREFIX" do
        expect(command).to receive(:run!).with(
          executable,
          a_hash_including(
            env: { "PATH" => PATH.new("#{HOMEBREW_PREFIX}/bin", "#{HOMEBREW_PREFIX}/sbin", ENV.fetch("PATH")) },
          ),
        )

        installer.install_phase(command:)
      end

      it "does not sandbox the executable" do
        allow(Sandbox).to receive(:available?).and_return(true)
        expect(Sandbox).not_to receive(:new)
        expect(command).to receive(:run!)

        installer.install_phase(command:)
      end
    end
  end
end
