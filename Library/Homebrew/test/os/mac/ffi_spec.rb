# typed: true
# frozen_string_literal: true

require "os/mac/ffi"

RSpec.describe MacOS::FFI, :needs_macos do
  it "loads the macOS FFI wrapper modules" do
    expect(MacOS::FFI::CoreFoundation).to be_a(Module)
    expect(MacOS::FFI::Foundation).to be_a(Module)
    expect(MacOS::FFI::LaunchServices).to be_a(Module)
    expect(MacOS::FFI::NativeLibrary).to be_a(Module)
    expect(MacOS::FFI::ObjectiveC).to be_a(Module)
  end
end
