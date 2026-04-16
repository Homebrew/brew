# typed: false
# frozen_string_literal: true

require "open3"
require "shellwords"

# This spec exercises a shell helper rather than a Ruby class API.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "vendor-install.sh" do
  let(:vendor_dir) { mktmpdir("vendor-install")/"vendor" }
  let(:vendor_root) { vendor_dir/"brew-rs" }
  let(:vendor_binary) { vendor_root/"bin/brew-rs" }
  let(:vendor_symlink) { vendor_root/"brew-rs" }
  let(:vendor_install_sh) { HOMEBREW_LIBRARY_PATH/"cmd/vendor-install.sh" }
  let(:check_vendor_script) do
    <<~SH
      source #{Shellwords.escape(vendor_install_sh.to_s)}
      VENDOR_DIR=#{Shellwords.escape(vendor_dir.to_s)}
      brew-rs-vendor-up-to-date
    SH
  end

  before do
    vendor_binary.dirname.mkpath
    vendor_binary.write("#!/bin/bash\n")
    vendor_binary.chmod(0755)
    File.utime(Time.at(2_000_000_000), Time.at(2_000_000_000), vendor_binary)
  end

  it "does not recreate the brew-rs launcher symlink while checking freshness" do
    _stdout, _stderr, status = Open3.capture3(
      { "HOMEBREW_LIBRARY" => HOMEBREW_LIBRARY_PATH.to_s },
      "/bin/bash",
      "-c",
      check_vendor_script,
    )

    expect([status.success?, vendor_symlink.exist?]).to eq([false, false])
  end

  it "treats the launcher symlink as part of the up-to-date vendor layout" do
    FileUtils.ln_s("bin/brew-rs", vendor_symlink)

    _stdout, _stderr, status = Open3.capture3(
      { "HOMEBREW_LIBRARY" => HOMEBREW_LIBRARY_PATH.to_s },
      "/bin/bash",
      "-c",
      check_vendor_script,
    )

    expect(status.success?).to be true
  end
end
# rubocop:enable RSpec/DescribeClass
