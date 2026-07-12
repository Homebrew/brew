# typed: true
# frozen_string_literal: true

require "os/mac/ffi/dyld"

RSpec.describe MacOS::FFI, :needs_macos do
  describe ".dyld_shared_cache_contains_path" do
    it "checks whether a path is in the dyld shared cache" do
      expect(described_class.dyld_shared_cache_contains_path("/usr/lib/libSystem.B.dylib")).to be(true).or be(false)
    end
  end
end
