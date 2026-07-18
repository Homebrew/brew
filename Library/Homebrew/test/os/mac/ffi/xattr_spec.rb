# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/xattr"

RSpec.describe MacOS::FFI, :needs_macos do
  describe ".copy_xattrs" do
    it "replaces destination extended attributes with source extended attributes" do
      mktmpdir do |tmpdir|
        source = tmpdir/"source"
        destination = tmpdir/"destination"
        source.write("source")
        destination.write("destination")

        described_class.set_xattr(source.to_s, "com.homebrew.test.source", "source")
        described_class.set_xattr(destination.to_s, "com.homebrew.test.destination", "destination")

        described_class.copy_xattrs(source.to_s, destination.to_s)

        destination_xattrs = described_class.list_xattrs(destination.to_s)
        expect(destination_xattrs).to include("com.homebrew.test.source")
        expect(destination_xattrs).not_to include("com.homebrew.test.destination")
        expect(described_class.get_xattr(destination.to_s, "com.homebrew.test.source")).to eq("source")
      end
    end
  end
end
