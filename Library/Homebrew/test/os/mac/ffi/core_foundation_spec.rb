# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/core_foundation"

RSpec.describe MacOS::FFI::CoreFoundation, :needs_macos do
  it "creates CoreFoundation strings, dictionaries and file URLs" do
    described_class.with_release_pool do |pool|
      string = pool.track(described_class.string_create("/tmp"))
      expect(string.null?).to be(false)

      expect(described_class.type_dictionary_key_call_backs.null?).to be(false)
      expect(described_class.type_dictionary_value_call_backs.null?).to be(false)
      expect(described_class.url_quarantine_properties_key.null?).to be(false)

      dictionary = pool.track(described_class.dictionary_create({ string => string }))
      expect(dictionary.null?).to be(false)

      url = pool.track(described_class.url_create_with_file_system_path(string))
      expect(url.null?).to be(false)
    end
  end

  describe ".with_release_pool" do
    it "returns the result of the block" do
      expect(described_class.with_release_pool { |_pool| "result" }).to eq("result")
    end

    it "releases tracked objects in reverse order once the block finishes" do
      released = []
      allow(described_class).to receive(:release) { |ptr| released << ptr }

      first = Fiddle::Pointer.new(1)
      second = Fiddle::Pointer.new(2)
      described_class.with_release_pool do |pool|
        expect(pool.track(first)).to eq(first)
        expect(pool.track(second)).to eq(second)
        expect(released).to be_empty
      end

      expect(released).to eq([second, first])
    end

    it "releases tracked objects when the block raises" do
      released = []
      allow(described_class).to receive(:release) { |ptr| released << ptr }

      pointer = Fiddle::Pointer.new(1)
      expect do
        described_class.with_release_pool do |pool|
          pool.track(pointer)
          raise "release pool test error"
        end
      end.to raise_error("release pool test error")

      expect(released).to eq([pointer])
    end

    it "does not track NULL pointers" do
      released = []
      allow(described_class).to receive(:release) { |ptr| released << ptr }

      described_class.with_release_pool do |pool|
        expect(pool.track(Fiddle::Pointer.new(0)).null?).to be(true)
      end

      expect(released).to be_empty
    end
  end
end
