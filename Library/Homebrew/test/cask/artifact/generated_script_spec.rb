# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::GeneratedScript, :cask do
  let(:cask) do
    Cask::Cask.new("with-generated-script") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      generated_script "installer.sh", content: <<~SH
        #!/bin/sh
        echo installed
      SH
    end
  end
  let(:artifact) { cask.artifacts.find { |candidate| candidate.is_a?(described_class) } }
  let(:path) { cask.staged_path/"installer.sh" }

  after { FileUtils.rm_rf cask.staged_path }

  it "writes an executable for another artifact to run" do
    artifact.install_phase

    expect(path).to exist.and be_executable.and have_attributes(read: "#!/bin/sh\necho installed\n")
  end

  it "serialises the script definition" do
    expect(artifact.to_args).to eq([
      "installer.sh",
      { content: "#!/bin/sh\necho installed\n" },
    ])
  end

  it "rejects paths outside the staged cask", :aggregate_failures do
    ["/tmp/installer.sh", "../installer.sh"].each do |script_path|
      expect do
        Cask::Cask.new("with-outside-generated-script") do
          version "1.2.3"
          sha256 :no_check
          url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

          generated_script script_path, content: "#!/bin/sh\n"
        end
      end.to raise_error(Cask::CaskInvalidError, /within the staged cask/)
    end
  end
end
