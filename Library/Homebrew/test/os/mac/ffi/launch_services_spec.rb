# typed: true
# frozen_string_literal: true

require "os/mac/ffi/launch_services"

RSpec.describe MacOS::FFI::LaunchServices, :needs_macos do
  it "loads quarantine constants from LaunchServices" do
    expect(described_class.quarantine_agent_name_key.null?).to be(false)
    expect(described_class.quarantine_data_url_key.null?).to be(false)
    expect(described_class.quarantine_origin_url_key.null?).to be(false)
    expect(described_class.quarantine_type_key.null?).to be(false)
    expect(described_class.quarantine_type_web_download.null?).to be(false)
  end
end
