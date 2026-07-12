# typed: true
# frozen_string_literal: true

require "os/mac/ffi/core_foundation"

RSpec.describe MacOS::FFI::CoreFoundation, :needs_macos do
  it "creates CoreFoundation strings, dictionaries and file URLs" do
    string = described_class.string_create("/tmp")
    expect(string.null?).to be(false)

    expect(described_class.type_dictionary_key_call_backs.null?).to be(false)
    expect(described_class.type_dictionary_value_call_backs.null?).to be(false)
    expect(described_class.url_quarantine_properties_key.null?).to be(false)

    dictionary = described_class.dictionary_create({ string => string })
    expect(dictionary.null?).to be(false)

    url = described_class.url_create_with_file_system_path(string)
    expect(url.null?).to be(false)
  end
end
