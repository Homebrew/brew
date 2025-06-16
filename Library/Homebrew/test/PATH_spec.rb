# frozen_string_literal: true

require "PATH"

RSpec.describe PATH do
  describe "#initialize" do
    it "can take multiple arguments" do
      expect(described_class.new("/path1", "/path2")).to eq("/path1:/path2")
    end

    it "can parse a mix of arrays and arguments" do
      expect(described_class.new(["/path1", "/path2"], "/path3")).to eq("/path1:/path2:/path3")
    end

    it "splits an existing PATH" do
      expect(described_class.new("/path1:/path2")).to eq(["/path1", "/path2"])
    end

    it "removes duplicates" do
      expect(described_class.new("/path1", "/path1")).to eq("/path1")
    end
  end

  describe "#to_ary" do
    it "returns a PATH array" do
      expect(described_class.new("/path1", "/path2").to_ary).to eq(["/path1", "/path2"])
    end

    it "does not allow mutating the original" do
      path = described_class.new("/path1", "/path2")
      path.to_ary << "/path3"

      expect(path).not_to include("/path3")
    end
  end

  describe "#to_str" do
    it "returns a PATH string" do
      expect(described_class.new("/path1", "/path2").to_str).to eq("/path1:/path2")
    end
  end

  describe "#prepend" do
    it "prepends a path to a PATH" do
      expect(described_class.new("/path1").prepend("/path2").to_str).to eq("/path2:/path1")
    end

    it "removes duplicates" do
      expect(described_class.new("/path1").prepend("/path1").to_str).to eq("/path1")
    end
  end

  describe "#append" do
    it "prepends a path to a PATH" do
      expect(described_class.new("/path1").append("/path2").to_str).to eq("/path1:/path2")
    end

    it "removes duplicates" do
      expect(described_class.new("/path1").append("/path1").to_str).to eq("/path1")
    end
  end

  describe "#insert" do
    it "inserts a path at a given index" do
      expect(described_class.new("/path1").insert(0, "/path2").to_str).to eq("/path2:/path1")
    end

    it "can insert multiple paths" do
      expect(described_class.new("/path1").insert(0, "/path2", "/path3")).to eq("/path2:/path3:/path1")
    end
  end

  describe "#==" do
    it "always returns false when comparing against something which does not respond to `#to_ary` or `#to_str`" do
      expect(described_class.new).not_to eq Object.new
    end
  end

  describe "#include?" do
    it "returns true if a path is included" do
      path = described_class.new("/path1", "/path2")
      expect(path).to include("/path1")
      expect(path).to include("/path2")
    end

    it "returns false if a path is not included" do
      expect(described_class.new("/path1")).not_to include("/path2")
    end

    it "returns false if the given string contains a separator" do
      expect(described_class.new("/path1", "/path2")).not_to include("/path1:")
    end
  end

  describe "#each" do
    it "loops through each path" do
      enum = described_class.new("/path1", "/path2").each

      expect(enum.next).to eq("/path1")
      expect(enum.next).to eq("/path2")
    end
  end

  describe "#select" do
    it "returns an object of the same class instead of an Array" do
      expect(described_class.new.select { true }).to be_a(described_class)
    end
  end

  describe "#reject" do
    it "returns an object of the same class instead of an Array" do
      expect(described_class.new.reject { true }).to be_a(described_class)
    end
  end

  describe "#existing" do
    it "returns a new PATH without non-existent paths" do
      allow(File).to receive(:directory?).with("/path1").and_return(true)
      allow(File).to receive(:directory?).with("/path2").and_return(false)

      path = described_class.new("/path1", "/path2")
      expect(path.existing.to_ary).to eq(["/path1"])
      expect(path.to_ary).to eq(["/path1", "/path2"])
    end

    it "returns nil instead of an empty #{described_class}" do
      expect(described_class.new.existing).to be_nil
    end
  end
end
