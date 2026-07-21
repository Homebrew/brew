# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::CommandWrapper, :cask do
  let(:cask) do
    Cask::Cask.new("with-command-wrapper") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      command_wrapper "example.wrapper.sh",
                      target:  "example",
                      content: <<~SH
                        #!/bin/sh
                        exec '/Applications/Example.app/Contents/MacOS/example' "$@"
                      SH
    end
  end
  let(:artifact) { cask.artifacts.find { |candidate| candidate.is_a?(described_class) } }
  let(:target) { cask.config.binarydir/"example" }

  around do |example|
    cask.staged_path.mkpath
    target.dirname.mkpath
    example.run
  ensure
    FileUtils.rm_f target
    FileUtils.rm_rf cask.staged_path
  end

  it "writes and links an executable command wrapper" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(target).to be_a_symlink.and have_attributes(read:        include("Contents/MacOS/example"),
                                                       executable?: true)
  end

  it "serialises the wrapper definition" do
    expect(artifact.to_args).to eq([
      "example.wrapper.sh",
      {
        target:  "example",
        content: "#!/bin/sh\nexec '/Applications/Example.app/Contents/MacOS/example' \"$@\"\n",
      },
    ])
  end
end
