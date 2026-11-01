# typed: true
# frozen_string_literal: true

require "system_command"

RSpec.describe "shims/shared/curl", type: :system do
  let(:config_dir) { mktmpdir }

  before do
    (config_dir/".curlrc").write "write-out = \"default-config-read\"\nurl = \"file://#{File::NULL}\"\n"
    (config_dir/"custom.curlrc").write 'write-out = "custom-config-read"'
    ENV["CURL_HOME"] = config_dir.to_s
    ENV["HOMEBREW_CURL"] = "/usr/bin/curl"
    # curl >= 8.18.0 refuses a `--cacert` file that does not exist.
    FileUtils.touch config_dir/"cert.pem"
    ENV["SSL_CERT_FILE"] = (config_dir/"cert.pem").to_s
  end

  it "disables the default config when adding certificate options" do
    expect(["-q", "--disable"].map do |disable|
      SystemCommand.run!(HOMEBREW_SHIMS_PATH/"shared/curl",
                         args: [disable, "--silent", "file://#{File::NULL}"]).stdout
    end).to eq(["", ""])
  end

  it "loads only the explicit config when adding certificate options" do
    expect(["-q", "--disable"].map do |disable|
      SystemCommand.run!(HOMEBREW_SHIMS_PATH/"shared/curl",
                         args: [disable, "--config", (config_dir/"custom.curlrc").to_s,
                                "--silent", "file://#{File::NULL}"]).stdout
    end).to eq(["custom-config-read", "custom-config-read"])
  end

  it "loads the default config when not disabled" do
    expect(SystemCommand.run!(HOMEBREW_SHIMS_PATH/"shared/curl",
                              args: ["--silent", "file://#{File::NULL}"]).stdout)
      .to eq("default-config-readdefault-config-read")
  end
end
