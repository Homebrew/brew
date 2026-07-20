# typed: strict
# frozen_string_literal: true

require "utils/clang"

RSpec.describe Utils::Clang do
  sig { returns(Pathname) }
  let(:config_dir) { Pathname(TEST_TMPDIR)/"clang-config" }

  after { FileUtils.rm_rf config_dir }

  specify "writes Clang system configuration files" do
    macos_version = MacOSVersion.new("14")
    allow(MacOS).to receive(:version).and_return(macos_version)

    described_class.write_system_config_files(
      config_dir:,
      macos_version:,
      kernel_version: 23,
      arch:           :arm64,
    )

    expect(config_dir.children.map { |path| path.basename.to_s }).to contain_exactly(
      "aarch64-apple-darwin23.cfg",
      "aarch64-apple-macosx14.cfg",
      "arm64-apple-darwin23.cfg",
      "arm64-apple-macosx14.cfg",
      "x86_64-apple-darwin23.cfg",
      "x86_64-apple-macosx14.cfg",
    )
    expect((config_dir/"arm64-apple-macosx14.cfg").read)
      .to eq("-isysroot #{MacOS::CLT::PKG_PATH}/SDKs/MacOSX14.sdk\n")
  end
end
