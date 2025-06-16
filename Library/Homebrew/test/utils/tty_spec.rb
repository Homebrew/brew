# frozen_string_literal: true

RSpec.describe Tty do
  describe "::strip_ansi" do
    it "removes ANSI escape codes from a string" do
      expect(described_class.strip_ansi("\033[36;7mhello\033[0m")).to eq("hello")
    end
  end

  describe "::width" do
    it "returns an Integer" do
      expect(described_class.width).to be_a(Integer)
    end

    it "cannot be negative" do
      expect(described_class.width).to be >= 0
    end
  end

  describe "::truncate" do
    it "truncates the text to the terminal width, minus 4, to account for '==> '" do
      allow(described_class).to receive(:width).and_return(15)

      expect(described_class.truncate("foobar something very long")).to eq("foobar some")
      expect(described_class.truncate("truncate")).to eq("truncate")
    end

    it "doesn't truncate the text if the terminal is unsupported, i.e. the width is 0" do
      allow(described_class).to receive(:width).and_return(0)
      expect(described_class.truncate("foobar something very long")).to eq("foobar something very long")
    end
  end

  context "when $stdout is not a TTY" do
    before do
      allow($stdout).to receive(:tty?).and_return(false)
    end

    it "returns an empty string for all colors" do
      expect(described_class.to_s).to eq("")
      expect(described_class.red.to_s).to eq("")
      expect(described_class.green.to_s).to eq("")
      expect(described_class.yellow.to_s).to eq("")
      expect(described_class.blue.to_s).to eq("")
      expect(described_class.magenta.to_s).to eq("")
      expect(described_class.cyan.to_s).to eq("")
      expect(described_class.default.to_s).to eq("")
    end
  end

  context "when $stdout is a TTY" do
    before do
      allow($stdout).to receive(:tty?).and_return(true)
    end

    it "returns ANSI escape codes for colors" do
      expect(described_class.to_s).to eq("")
      expect(described_class.red.to_s).to eq("\033[31m")
      expect(described_class.green.to_s).to eq("\033[32m")
      expect(described_class.yellow.to_s).to eq("\033[33m")
      expect(described_class.blue.to_s).to eq("\033[34m")
      expect(described_class.magenta.to_s).to eq("\033[35m")
      expect(described_class.cyan.to_s).to eq("\033[36m")
      expect(described_class.default.to_s).to eq("\033[39m")
    end

    it "returns an empty string for all colors when HOMEBREW_NO_COLOR is set" do
      ENV["HOMEBREW_NO_COLOR"] = "1"
      expect(described_class.to_s).to eq("")
      expect(described_class.red.to_s).to eq("")
      expect(described_class.green.to_s).to eq("")
      expect(described_class.yellow.to_s).to eq("")
      expect(described_class.blue.to_s).to eq("")
      expect(described_class.magenta.to_s).to eq("")
      expect(described_class.cyan.to_s).to eq("")
      expect(described_class.default.to_s).to eq("")
    end
  end
end
