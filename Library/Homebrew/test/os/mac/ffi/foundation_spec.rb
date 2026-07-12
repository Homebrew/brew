# typed: true
# frozen_string_literal: true

require "os/mac/ffi/foundation"

RSpec.describe MacOS::FFI::Foundation, :needs_macos do
  describe ".trash_item" do
    it "moves a file to the user's Trash" do
      trashed_path = T.let(nil, T.nilable(String))

      mktmpdir do |tmpdir|
        path = tmpdir/"homebrew-trash-ffi-test"
        path.write("trash")

        trashed_path = described_class.trash_item(path.to_s)

        expect(path).not_to exist
        raise "Failed to trash #{path}" unless trashed_path

        expect(Pathname(trashed_path)).to exist
      ensure
        FileUtils.rm_rf(trashed_path) if trashed_path
      end
    end
  end
end
