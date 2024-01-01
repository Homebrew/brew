# frozen_string_literal: true

require "formula"

describe Formula do
  describe "::new" do
    it "selects stable by default" do
      f = formula do
        url "foo-1.0"
        head "foo"
      end

      expect(f).to be_stable
    end

    it "selects stable when exclusive" do
      f = formula { url "foo-1.0" }
      expect(f).to be_stable
    end

    it "selects HEAD when exclusive" do
      f = formula { head "foo" }
      expect(f).to be_head
    end

    it "does not select an incomplete spec" do
      f = formula do
        sha256 TEST_SHA256
        version "1.0"
        head "foo"
      end

      expect(f).to be_head
    end

    it "does not set an incomplete stable spec" do
      f = formula do
        sha256 TEST_SHA256
        head "foo"
      end

      expect(f.stable).to be_nil
      expect(f).to be_head
    end

    it "selects HEAD when requested" do
      f = formula("test", spec: :head) do
        url "foo-1.0"
        head "foo"
      end

      expect(f).to be_head
    end

    it "does not raise an error for a missing spec" do
      f = formula("test", spec: :head) do
        url "foo-1.0"
      end

      expect(f).to be_stable
    end
  end
end
