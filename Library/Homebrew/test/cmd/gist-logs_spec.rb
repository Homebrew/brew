# frozen_string_literal: true

require "cmd/gist-logs"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::GistLogs do
  it_behaves_like "parseable arguments"

  describe ".truncate_text_to_approximate_size" do
    let(:glue) { "\n[...snip...]\n" } # hard-coded copy from truncate_text_to_approximate_size

    it "truncates long text to approximate size" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n)
      expect(s.length).to eq(n)
      expect(s).to match(/^x+#{Regexp.escape(glue)}x+$/)
    end

    it "respects front_weight: 0.0" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n, front_weight: 0.0)
      expect(s).to eq(glue + ("x" * (n - glue.length)))
    end

    it "respects front_weight: 1.0" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n, front_weight: 1.0)
      expect(s).to eq(("x" * (n - glue.length)) + glue)
    end
  end
end
