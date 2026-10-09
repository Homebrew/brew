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

  describe "::version_changes" do
    it "leaves a single entry on one line" do
      expect(described_class.version_changes([version_change("b4", "0.15", "0.16")])).to eq(["b4 0.15 -> 0.16"])
    end

    it "aligns multiple entries" do
      changes = [version_change("cffi", "2.1.1"), version_change("libgit2", "1.9", "1.10")]

      expect(described_class.version_changes(changes)).to eq([
        "cffi     2.1.1",
        "libgit2  1.9   -> 1.10",
      ])
    end

    it "aligns a large mixed list of package names and versions" do
      upgrades = [
        version_change("sqlite", "3.53.1", "3.53.2", size: "2.4MB"),
        version_change("docker", "29.5.2", "29.6.0", size: "9.3MB"),
        version_change("gh", "2.93.0", "2.95.0", size: "13.4MB"),
        version_change("python@3.14", "3.14.5", "3.14.6", size: "19.2MB"),
        version_change("pnpm", "11.5.1", "11.8.0", size: "4MB"),
        version_change("usage", "3.4.0", "3.5.2", size: "2.9MB"),
        version_change("certifi", "2026.5.20", "2026.6.17", size: "5.7KB"),
        version_change("libvmaf", "3.1.0", "3.2.0", size: "1.2MB"),
        version_change("kubernetes-cli", "1.36.1", "1.36.2", size: "18.2MB"),
        version_change("jq", "1.8.1", "1.8.2", size: "441KB"),
        version_change("mise", "2026.6.0", "2026.6.11", size: "34.8MB"),
        version_change("sdl2", "2.32.70", size: "636.8KB"),
        version_change("opencode-desktop", "1.14.48", "1.17.9"),
        version_change("slack", "4.48.102", "4.50.140"),
        version_change("spotify", "1.2.84.476", "1.2.92.148"),
        version_change("visual-studio-code", "1.111.0", "1.125.1"),
      ]

      expect(described_class.version_changes(upgrades)).to eq([
        "sqlite              3.53.1     -> 3.53.2      (2.4MB)",
        "docker              29.5.2     -> 29.6.0      (9.3MB)",
        "gh                  2.93.0     -> 2.95.0      (13.4MB)",
        "python@3.14         3.14.5     -> 3.14.6      (19.2MB)",
        "pnpm                11.5.1     -> 11.8.0      (4MB)",
        "usage               3.4.0      -> 3.5.2       (2.9MB)",
        "certifi             2026.5.20  -> 2026.6.17   (5.7KB)",
        "libvmaf             3.1.0      -> 3.2.0       (1.2MB)",
        "kubernetes-cli      1.36.1     -> 1.36.2      (18.2MB)",
        "jq                  1.8.1      -> 1.8.2       (441KB)",
        "mise                2026.6.0   -> 2026.6.11   (34.8MB)",
        "sdl2                2.32.70                   (636.8KB)",
        "opencode-desktop    1.14.48    -> 1.17.9",
        "slack               4.48.102   -> 4.50.140",
        "spotify             1.2.84.476 -> 1.2.92.148",
        "visual-studio-code  1.111.0    -> 1.125.1",
      ])
    end
  end
end
