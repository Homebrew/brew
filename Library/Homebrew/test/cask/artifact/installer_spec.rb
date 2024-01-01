# frozen_string_literal: true

describe Cask::Artifact::Installer, :cask do
  subject(:installer) { described_class.new(cask, **args) }

  let(:staged_path) { mktmpdir }
  let(:cask) { instance_double(Cask::Cask, staged_path: staged_path) }

  let(:command) { SystemCommand }

  let(:args) { {} }

  describe "#install_phase" do
    context "when given a manual installer" do
      let(:args) { { manual: "installer" } }

      it "shows a message prompting to run the installer manually" do
        expect do
          installer.install_phase(command: command)
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

        installer.install_phase(command: command)
      end
    end
  end
end
