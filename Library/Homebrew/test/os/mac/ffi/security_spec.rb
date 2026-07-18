# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/security"

RSpec.describe MacOS::FFI::Security, :needs_macos do
  it "uses designated requirements to identify signed code" do
    requirement = described_class.designated_requirement("/bin/ls")
    expect(requirement).not_to be_nil

    if requirement
      aggregate_failures do
        expect(requirement).to include('identifier "com.apple.ls"')
        expect(described_class.requirement_match("/bin/ls", requirement)).to be(true)
        expect(described_class.requirement_match("/bin/cat", requirement)).to be(false)
        expect(described_class.requirement_match("/does/not/exist", requirement)).to be_nil
      end
    end
  end
end
