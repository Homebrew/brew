# typed: strict
# frozen_string_literal: true

require "utils/formatter"

RSpec.describe Formatter do
  describe "::columns" do
    before do
      allow($stdout).to receive(:tty?).and_return(true)
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:width).and_return(80)
    end

    it "stretches few short items into wide columns that fill the terminal" do
      first_row = described_class.columns(%w[aa bb cc dd]).lines.fetch(0).chomp

      expect(first_row.index("bb")).to be > 2
    end

    it "uses tighter columns when min_width fits more columns than the item count" do
      default_first_row = described_class.columns(%w[aa bb cc dd]).lines.fetch(0).chomp
      pinned_first_row = described_class.columns(%w[aa bb cc dd], min_width: 4).lines.fetch(0).chomp

      expect(pinned_first_row.index("bb")).to be < default_first_row.index("bb")
    end

    it "produces matching column widths for two calls sharing the same min_width" do
      many = (1..20).map { |i| "item#{i}" }
      few = %w[a b c]
      shared_min_width = (many + few).map(&:length).max || 0

      many_first_row = described_class.columns(many, min_width: shared_min_width).lines.fetch(0).chomp
      few_first_row = described_class.columns(few, min_width: shared_min_width).lines.fetch(0).chomp

      expect(many_first_row.index("item3")).to eq(few_first_row.index("b"))
    end
  end
end
