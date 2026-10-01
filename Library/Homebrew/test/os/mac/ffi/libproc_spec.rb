# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/libproc"

RSpec.describe MacOS::FFI::LibProc, :needs_macos do
  describe ".parent_pid" do
    it "returns the parent of the current process" do
      expect(described_class.parent_pid(Process.pid)).to eq Process.ppid
    end

    it "returns the parent of a process owned by another user" do
      expect(described_class.parent_pid(1)).to eq 0
    end

    it "returns nil for a process that does not exist" do
      expect(described_class.parent_pid(-1)).to be_nil
    end
  end

  describe ".real_uid" do
    it "returns the real user ID of the current process" do
      expect(described_class.real_uid(Process.pid)).to eq Process.uid
    end

    it "returns the real user ID of a process owned by another user" do
      expect(described_class.real_uid(1)).to eq 0
    end

    it "returns nil for a process that does not exist" do
      expect(described_class.real_uid(-1)).to be_nil
    end
  end
end
