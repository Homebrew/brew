# typed: false
# frozen_string_literal: true

require "os/mac/ffi/native_library"

RSpec.describe MacOS::FFI::NativeLibrary, :needs_macos do
  let(:library) do
    Module.new do
      extend MacOS::FFI::NativeLibrary

      use_library "/usr/lib/libSystem.B.dylib"

      def self.process_id
        function("getpid", [], Fiddle::TYPE_INT).call
      end
    end
  end

  it "loads native functions from a system library" do
    expect(library.process_id).to eq(Process.pid)
  end
end
