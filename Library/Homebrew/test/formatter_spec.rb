# frozen_string_literal: true

require "utils/formatter"
require "utils/tty"

RSpec.describe Formatter do
  describe "::columns" do
    subject(:columns) { described_class.columns(input) }

    let(:input) do
      %w[
        aa
        bbb
        ccc
        dd
      ]
    end

    it "doesn't output columns if $stdout is not a TTY." do
      allow_any_instance_of(IO).to receive(:tty?).and_return(false)
      allow(Tty).to receive(:width).and_return(10)

      expect(columns).to eq(
        "aa\n" \
        "bbb\n" \
        "ccc\n" \
        "dd\n",
      )
    end

    describe "$stdout is a TTY" do
      it "outputs columns" do
        allow_any_instance_of(IO).to receive(:tty?).and_return(true)
        allow(Tty).to receive(:width).and_return(10)

        expect(columns).to eq(
          "aa    ccc\n" \
          "bbb   dd\n",
        )
      end

      it "outputs only one line if everything fits" do
        allow_any_instance_of(IO).to receive(:tty?).and_return(true)
        allow(Tty).to receive(:width).and_return(20)

        expect(columns).to eq(
          "aa   bbb  ccc  dd\n",
        )
      end
    end

    describe "with empty input" do
      let(:input) { [] }

      it { is_expected.to eq("\n") }
    end
  end

  describe "::format_help_text" do
    it "indents subcommand descriptions" do
      # The following example help text was carefully crafted to test all five regular expressions in the method.
      # Also, the text is designed in such a way such that options (e.g. `--foo`) would be wrapped to the
      # beginning of new lines if normal wrapping was used. This is to test that the method works as expected
      # and doesn't allow options to start new lines. Be careful when changing the text so these checks aren't lost.
      text = <<~HELP
        Usage: brew command [<options>] <formula>...

        This is a test command.
        Single line breaks are removed, but the entire line is still wrapped at the correct point.

        Paragraphs are preserved but
        are also wrapped at the right point. Here's some more filler text to get this line to be long enough.
        Options, for example: --foo, are never placed at the start of a line.

        `brew command` [`state`]:
        Display the current state of the command.

        `brew command` (`on`|`off`):
        Turn the command on or off respectively.

          -f, --foo                        This line is wrapped with a hanging indent. --test. The --test option isn't at the start of a line.
          -b, --bar                        The following option is not left on its own: --baz
          -h, --help                       Show this message.
      HELP

      expected = <<~HELP
        Usage: brew command [<options>] <formula>...

        This is a test command. Single line breaks are removed, but the entire line is
        still wrapped at the correct point.

        Paragraphs are preserved but are also wrapped at the right point. Here's some
        more filler text to get this line to be long enough. Options, for
        example: --foo, are never placed at the start of a line.

        `brew command` [`state`]:
            Display the current state of the command.

        `brew command` (`on`|`off`):
            Turn the command on or off respectively.

          -f, --foo                        This line is wrapped with a hanging
                                           indent. --test. The --test option isn't at
                                           the start of a line.
          -b, --bar                        The following option is not left on its
                                           own: --baz
          -h, --help                       Show this message.
      HELP

      expect(described_class.format_help_text(text, width: 80)).to eq expected
    end
  end

  describe "::truncate" do
    it "returns the original string if it's shorter than max length" do
      expect(described_class.truncate("short", max: 10)).to eq("short")
    end

    it "truncates strings longer than max length" do
      expect(described_class.truncate("this is a long string", max: 10)).to eq("this is...")
    end

    it "uses custom omission string" do
      expect(described_class.truncate("this is a long string", max: 10, omission: " [...]")).to eq("this [...]")
    end
  end

  describe ".disk_usage_readable_size_unit" do
    it "returns size and unit for bytes" do
      expect(described_class.disk_usage_readable_size_unit(500)).to eq([500, "B"])
    end

    it "converts to KB for sizes >= 1000" do
      size, unit = described_class.disk_usage_readable_size_unit(1500)
      expect(unit).to eq("KB")
      expect(size).to eq(1.5)
    end

    it "converts to MB for sizes >= 1000000" do
      size, unit = described_class.disk_usage_readable_size_unit(2_500_000)
      expect(unit).to eq("MB")
      expect(size).to eq(2.5)
    end

    it "converts to GB for sizes >= 1000000000" do
      size, unit = described_class.disk_usage_readable_size_unit(3_500_000_000)
      expect(unit).to eq("GB")
      expect(size).to eq(3.5)
    end

    it "respects precision parameter" do
      _, unit = described_class.disk_usage_readable_size_unit(999.5, precision: 0)
      expect(unit).to eq("KB")
    end
  end

  describe ".disk_usage_readable" do
    it "formats bytes as human-readable sizes" do
      expect(described_class.disk_usage_readable(1)).to eq("1B")
      expect(described_class.disk_usage_readable(999)).to eq("999B")
      expect(described_class.disk_usage_readable(1000)).to eq("1KB")
      expect(described_class.disk_usage_readable(1025)).to eq("1KB")
      expect(described_class.disk_usage_readable(4_404_020)).to eq("4.4MB")
      expect(described_class.disk_usage_readable(4_509_715_660)).to eq("4.5GB")
    end
  end

  describe ".number_readable" do
    it "returns a string with thousands separators" do
      expect(described_class.number_readable(1)).to eq("1")
      expect(described_class.number_readable(1_000)).to eq("1,000")
      expect(described_class.number_readable(1_000_000)).to eq("1,000,000")
    end
  end

  describe ".redact_secrets" do
    it "replaces secrets with asterisks" do
      expect(described_class.redact_secrets("password123", ["password123"])).to eq("******")
    end

    it "replaces multiple secrets" do
      input = "user: admin, pass: secret"
      expect(described_class.redact_secrets(input, ["admin", "secret"])).to eq("user: ******, pass: ******")
    end

    it "handles empty secrets array" do
      expect(described_class.redact_secrets("keep this", [])).to eq("keep this")
    end

    it "returns frozen string" do
      result = described_class.redact_secrets("test", ["foo"])
      expect(result).to be_frozen
    end
  end
end
