# typed: strict
# frozen_string_literal: true

require "io/console"
require "pty"

RSpec.describe Tty do
  describe "::strip_ansi" do
    it "removes ANSI escape codes from a string" do
      expect(described_class.strip_ansi("\033[36;7mhello\033[0m")).to eq("hello")
    end

    it "removes terminal control strings, C1 controls, bells, and carriage returns" do
      string = [
        "\e[31mred\e[0m",
        "\e]0;title\a",
        "\ePdevice-control\e\\",
        "\e_application-command\e\\",
        "\e^privacy-message\e\\",
        "\u009B31mC1 red\u009B0m",
        "\u009Dtitle\u009C",
        "bell\a carriage\rreturn",
        "lone escape\e",
      ].join(" ")

      expect(described_class.strip_ansi(string)).to eq("red     C1 red  bell carriagereturn lone escape")
    end

    it "sanitises binary strings without changing their encoding" do
      string = "A\xFF\e[31mB".b
      sanitised = described_class.strip_ansi(string)

      expect([sanitised, sanitised.encoding]).to eq(["A\xFFB".b, Encoding::ASCII_8BIT])
    end
  end

  describe "::collapse_carriage_returns" do
    it "keeps only the final segment of a carriage-return-delimited progress bar" do
      expect(described_class.collapse_carriage_returns("#\r##\r### 100%")).to eq("### 100%")
    end

    it "collapses carriage returns independently on each real line" do
      expect(described_class.collapse_carriage_returns("a\rb\nc\rd")).to eq("b\nd")
    end

    it "returns the string unchanged when it has no carriage returns" do
      expect(described_class.collapse_carriage_returns("curl: (7) Couldn't connect to server")).to(
        eq("curl: (7) Couldn't connect to server"),
      )
    end

    it "keeps the last written content when the string ends with a trailing carriage return" do
      expect(described_class.collapse_carriage_returns("### 50%\r")).to eq("### 50%")
    end
  end

  describe "::begin_synchronized_update" do
    it "returns the DEC private mode 2026 set sequence" do
      expect(described_class.begin_synchronized_update).to eq("\033[?2026h")
    end
  end

  describe "::end_synchronized_update" do
    it "returns the DEC private mode 2026 reset sequence" do
      expect(described_class.end_synchronized_update).to eq("\033[?2026l")
    end
  end

  describe "::size" do
    before do
      described_class.remove_instance_variable(:@size) if described_class.instance_variable_defined?(:@size)
      allow(Utils).to receive(:popen_read_text).and_raise("unexpected subprocess")
    end

    after do
      described_class.remove_instance_variable(:@size) if described_class.instance_variable_defined?(:@size)
    end

    it "reads and memoises the terminal size without a subprocess" do
      PTY.open do |controller, terminal|
        controller.winsize = [40, 160]
        $stdin.reopen(terminal)
        size = described_class.size
        controller.winsize = [50, 180]

        expect([size, described_class.size]).to eq([[40, 160], [40, 160]])
      end
    end

    it "returns nil when stdin is redirected" do
      $stdin.reopen(File::NULL)

      expect(described_class.size).to be_nil
    end

    it "returns nil when stdin is closed" do
      original_stdin = $stdin
      $stdin = $stdin.dup
      $stdin.close

      expect(described_class.size).to be_nil
    ensure
      $stdin = original_stdin
    end

    it "memoises a failed terminal size probe" do
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdin).to receive(:winsize).and_invoke(proc { raise Errno::ENOTTY }, proc { [40, 160] })

      # We call this twice to check the failure is memoised
      expect([described_class.size, described_class.size]).to eq([nil, nil])
    end

    it "does not expose an unfinished size to another thread" do
      probe_started = Queue.new
      release_probe = Queue.new
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stdin).to receive(:winsize).and_invoke(
        proc {
          probe_started << true
          release_probe.pop
          [40, 160]
        },
        proc { [40, 160] },
      )

      probing_thread = Thread.new { described_class.size }
      probe_started.pop(timeout: 5)

      expect(described_class.size).to eq([40, 160])
    ensure
      release_probe&.push(true)
      probing_thread&.value
    end
  end

  describe "::width" do
    specify do
      expect(described_class.width).to be_a(Integer)
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
