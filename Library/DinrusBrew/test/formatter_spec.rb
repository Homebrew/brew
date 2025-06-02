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
end
