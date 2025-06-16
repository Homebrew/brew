# frozen_string_literal: true

require "utils/github/actions"

RSpec.describe GitHub::Actions::Annotation do
  let(:message) { "lorem ipsum" }

  describe "#new" do
    it "fails when the type is wrong" do
      expect do
        described_class.new(:fatal, message, file: "file.txt")
      end.to raise_error(ArgumentError)
    end
  end

  describe "#to_s" do
    it "escapes newlines" do
      annotation = described_class.new(:warning, <<~EOS, file: "file.txt")
        lorem
        ipsum
      EOS

      expect(annotation.to_s).to eq "::warning file=file.txt::lorem%0Aipsum%0A"
    end

    it "allows specifying the file" do
      annotation = described_class.new(:warning, "lorem ipsum", file: "file.txt")

      expect(annotation.to_s).to eq "::warning file=file.txt::lorem ipsum"
    end

    it "allows specifying the title" do
      annotation = described_class.new(:warning, "lorem ipsum", file: "file.txt", title: "foo")

      expect(annotation.to_s).to eq "::warning file=file.txt,title=foo::lorem ipsum"
    end

    it "allows specifying the file and line" do
      annotation = described_class.new(:error, "lorem ipsum", file: "file.txt", line: 3)

      expect(annotation.to_s).to eq "::error file=file.txt,line=3::lorem ipsum"
    end

    it "allows specifying the file, line and column" do
      annotation = described_class.new(:error, "lorem ipsum", file: "file.txt", line: 3, column: 18)

      expect(annotation.to_s).to eq "::error file=file.txt,line=3,col=18::lorem ipsum"
    end
  end
end
