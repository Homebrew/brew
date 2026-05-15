# typed: false
# frozen_string_literal: true

require "commit_message"

RSpec.describe Homebrew::CommitMessage do
  describe ".parse" do
    it "parses subject, body, and trailers" do
      message = "Update foo\n\nSome body text.\n\nCo-authored-by: Alice <a@b.com>\nSigned-off-by: Bob <b@b.com>\n"
      subject, body, trailers = described_class.parse(message)
      expect(subject).to eq("Update foo")
      expect(body).to eq("Some body text.")
      expect(trailers).to include("Co-authored-by: Alice <a@b.com>")
      expect(trailers).to include("Signed-off-by: Bob <b@b.com>")
    end

    it "handles messages with only a subject" do
      subject, body, trailers = described_class.parse("Subject only\n")
      expect(subject).to eq("Subject only")
      expect(body).to eq("")
      expect(trailers).to eq("")
    end

    it "handles empty messages" do
      expect(described_class.parse("")).to eq(["", "", ""])
    end
  end

  describe "#subject, #body, #trailers" do
    it "exposes parsed components" do
      cm = described_class.new("Fix bug\n\nBody here.\n\nCloses: #123\nFixes: #456\nReviewed-by: Carol <c@c.com>\n")
      expect(cm.subject).to eq("Fix bug")
      expect(cm.body).to eq("Body here.")
      expect(cm.trailers).to include("Closes: #123")
      expect(cm.trailers).to include("Fixes: #456")
      expect(cm.trailers).to include("Reviewed-by: Carol <c@c.com>")
    end

    it "recognizes standard Git trailers beyond -by: patterns" do
      message = "Subject\n\nBody.\n\nChange-Id: I1234\nReviewed-on: https://example.com\n"
      cm = described_class.new(message)
      expect(cm.trailers).to include("Change-Id: I1234")
      expect(cm.trailers).to include("Reviewed-on: https://example.com")
    end

    it "does not extract trailer-like text from mid-body" do
      message = "Subject\n\nSome text.\nCloses: #99\nMore text.\n\nCo-authored-by: D <d@d.com>\n"
      cm = described_class.new(message)
      expect(cm.body).to include("Closes: #99")
      expect(cm.body).to include("More text.")
      expect(cm.trailers).to eq("Co-authored-by: D <d@d.com>")
    end

    it "returns empty trailers when there are none" do
      cm = described_class.new("Subject\n\nJust a body with no trailers.\n")
      expect(cm.subject).to eq("Subject")
      expect(cm.body).to eq("Just a body with no trailers.")
      expect(cm.trailers).to eq("")
    end

    it "deduplicates trailer lines" do
      message = "Subject\n\nBody.\n\nCo-authored-by: A <a@a.com>\nCo-authored-by: A <a@a.com>\n"
      cm = described_class.new(message)
      expect(cm.trailers).to eq("Co-authored-by: A <a@a.com>")
    end
  end

  describe "#to_s" do
    it "reconstructs a message from its parts" do
      message = "Subject\n\nBody text.\n\nCo-authored-by: A <a@a.com>\n"
      cm = described_class.new(message)
      expect(cm.to_s).to eq("Subject\n\nBody text.\n\nCo-authored-by: A <a@a.com>")
    end

    it "omits empty body and trailers" do
      cm = described_class.new("Subject only\n")
      expect(cm.to_s).to eq("Subject only")
    end
  end

  describe "#normalize" do
    it "strips trailing whitespace from lines" do
      message = "Subject  \n\nBody line.   \n\nTrailer-Key: value  \n"
      normalized = described_class.new(message).normalize
      expect(normalized.subject).to eq("Subject")
      expect(normalized.body).to eq("Body line.")
      expect(normalized.trailers).to eq("Trailer-Key: value")
    end

    it "collapses excessive blank lines" do
      message = "Subject\n\n\n\n\nBody line 1.\n\n\n\n\nBody line 2.\n\nTrailer: val\n"
      normalized = described_class.new(message).normalize
      expect(normalized.body).to eq("Body line 1.\n\nBody line 2.")
    end

    it "deduplicates trailer lines" do
      message = "Subject\n\nBody.\n\nCo-authored-by: A <a@a.com>\nCo-authored-by: A <a@a.com>\n"
      normalized = described_class.new(message).normalize
      expect(normalized.trailers).to eq("Co-authored-by: A <a@a.com>")
    end

    it "handles empty messages" do
      normalized = described_class.new("").normalize
      expect(normalized.subject).to eq("")
      expect(normalized.body).to eq("")
      expect(normalized.trailers).to eq("")
    end

    it "round-trips a clean message" do
      message = "Subject\n\nBody text.\n\nCo-authored-by: A <a@a.com>\n"
      cm = described_class.new(message)
      expect(cm.normalize.to_s).to eq(cm.to_s)
    end
  end
end
