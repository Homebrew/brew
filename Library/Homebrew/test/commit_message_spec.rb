# typed: false
# frozen_string_literal: true

require "commit_message"

RSpec.describe Homebrew::CommitMessage do
  describe ".parse" do
    it "parses a subject-only message" do
      msg = described_class.parse("Fix something")
      expect(msg.subject).to eq("Fix something")
      expect(msg.body).to eq("")
      expect(msg.trailers).to eq("")
    end

    it "parses subject and body" do
      msg = described_class.parse("Fix something\n\nThis is the body.\nWith two lines.")
      expect(msg.subject).to eq("Fix something")
      expect(msg.body).to eq("This is the body.\nWith two lines.")
      expect(msg.trailers).to eq("")
    end

    it "parses subject, body and Co-authored-by trailer" do
      message = <<~MSG
        Fix something

        This is the body.

        Co-authored-by: User <user@example.com>
      MSG
      msg = described_class.parse(message)
      expect(msg.subject).to eq("Fix something")
      expect(msg.body).to eq("This is the body.")
      expect(msg.trailers).to eq("Co-authored-by: User <user@example.com>")
    end

    it "parses multiple trailers" do
      message = <<~MSG
        Fix something

        Co-authored-by: User1 <u1@example.com>
        Signed-off-by: User2 <u2@example.com>
      MSG
      msg = described_class.parse(message)
      expect(msg.subject).to eq("Fix something")
      expect(msg.trailers).to eq(
        "Co-authored-by: User1 <u1@example.com>\nSigned-off-by: User2 <u2@example.com>",
      )
    end

    it "recognizes Closes trailer" do
      message = "Fix bug\n\nCloses #123"
      msg = described_class.parse(message)
      expect(msg.trailers).to eq("Closes #123")
      expect(msg.body).to eq("")
    end

    it "recognizes Fixes trailer" do
      message = "Fix bug\n\nFixes #456"
      msg = described_class.parse(message)
      expect(msg.trailers).to eq("Fixes #456")
    end

    it "recognizes Reviewed-on trailer" do
      message = "Fix bug\n\nReviewed-on: https://example.com/review/1"
      msg = described_class.parse(message)
      expect(msg.trailers).to eq("Reviewed-on: https://example.com/review/1")
    end

    it "recognizes Change-Id trailer" do
      message = "Fix bug\n\nChange-Id: I1234567890abcdef"
      msg = described_class.parse(message)
      expect(msg.trailers).to eq("Change-Id: I1234567890abcdef")
    end

    it "deduplicates identical trailers" do
      message = <<~MSG
        Fix something

        Co-authored-by: User <u@example.com>
        Co-authored-by: User <u@example.com>
      MSG
      msg = described_class.parse(message)
      expect(msg.trailers).to eq("Co-authored-by: User <u@example.com>")
    end

    it "collapses excessive blank lines in body" do
      message = "Fix something\n\nLine 1\n\n\n\n\nLine 2"
      msg = described_class.parse(message)
      expect(msg.body).to eq("Line 1\n\nLine 2")
    end

    it "handles empty message" do
      msg = described_class.parse("")
      expect(msg.subject).to eq("")
      expect(msg.body).to eq("")
      expect(msg.trailers).to eq("")
    end
  end

  describe "#normalize" do
    it "strips trailing whitespace from all lines" do
      msg = described_class.new(
        subject:  "Fix something   ",
        body:     "Line 1   \nLine 2  ",
        trailers: "Co-authored-by: User <u@example.com>  ",
      )
      normalized = msg.normalize
      expect(normalized.subject).to eq("Fix something")
      expect(normalized.body).to eq("Line 1\nLine 2")
      expect(normalized.trailers).to eq("Co-authored-by: User <u@example.com>")
    end

    it "collapses 3+ consecutive blank lines into 2 in body" do
      msg = described_class.new(subject: "Fix", body: "A\n\n\n\nB")
      normalized = msg.normalize
      expect(normalized.body).to eq("A\n\nB")
    end

    it "trims leading and trailing blank lines from body" do
      msg = described_class.new(subject: "Fix", body: "\n\nActual body\n\n")
      normalized = msg.normalize
      expect(normalized.body).to eq("Actual body")
    end

    it "trims leading and trailing blank lines from trailers" do
      msg = described_class.new(subject: "Fix", trailers: "\n\nCo-authored-by: U <u@x.com>\n\n")
      normalized = msg.normalize
      expect(normalized.trailers).to eq("Co-authored-by: U <u@x.com>")
    end
  end

  describe "#to_s" do
    it "formats subject only" do
      msg = described_class.new(subject: "Fix something")
      expect(msg.to_s).to eq("Fix something")
    end

    it "formats subject and body" do
      msg = described_class.new(subject: "Fix something", body: "Details here.")
      expect(msg.to_s).to eq("Fix something\n\nDetails here.")
    end

    it "formats subject, body and trailers" do
      msg = described_class.new(
        subject:  "Fix something",
        body:     "Details here.",
        trailers: "Co-authored-by: User <u@example.com>",
      )
      expect(msg.to_s).to eq("Fix something\n\nDetails here.\n\nCo-authored-by: User <u@example.com>")
    end
  end

  describe "round-trip" do
    it "preserves a well-formed message through parse and to_s" do
      original = "Fix something\n\nBody text.\n\nCo-authored-by: User <u@example.com>"
      msg = described_class.parse(original)
      expect(msg.to_s).to eq(original)
    end
  end
end
