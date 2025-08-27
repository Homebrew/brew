# frozen_string_literal: true

require "cask/cask"
require "cask/installer"
require "support/helper/cask/install_helper"

RSpec.describe Cask::Artifact::ShimScript, :cask do
  include InstallHelper

  let(:cask_token) { "shim-script-test" }
  let(:binary_rel) { "MyApp.app/Contents/MacOS/mytool" }

  let(:cask) do
    Cask::Cask.new(cask_token) do
      version "1.0"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"

      # Create a shim for an imaginary tool inside the staged dir
      shim_script binary_rel, target: cask_token.to_s, args: ["--flag"], env: { "FOO" => "bar" }
    end
  end

  it "creates and removes a shim script" do
    installer = InstallHelper.install_without_artifacts(cask)

    # Ensure a fake binary exists to point to
    staged_binary = cask.staged_path/binary_rel
    staged_binary.dirname.mkpath
    staged_binary.write("#!/bin/sh\necho ok\n")
    FileUtils.chmod("+x", staged_binary)

    installer.install_artifacts

    shim_path = HOMEBREW_PREFIX/"bin"/cask_token
    expect(shim_path).to exist
    expect(File.read(shim_path)).to include("exec \"")

    installer.uninstall_artifacts(clear: true)

    expect(shim_path).not_to exist
  end
end
