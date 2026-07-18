# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/objective_c"

RSpec.describe MacOS::FFI::ObjectiveC, :needs_macos do
  it "looks up Objective-C classes, selectors and sends messages" do
    file_manager_class = described_class.class_get("NSFileManager")
    expect(file_manager_class.null?).to be(false)

    expect(described_class.selector("defaultManager").null?).to be(false)

    file_manager = described_class.message_send(
      file_manager_class,
      "defaultManager",
      [],
      Fiddle::TYPE_VOIDP,
    )
    expect(file_manager.null?).to be(false)
  end
end
