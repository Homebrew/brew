# typed: strict
# frozen_string_literal: true

require "upgrade"

RSpec.describe Homebrew::Upgrade do
  describe "::format_upgrade_summary" do
    it "sorts alphabetically and aligns a large mixed list of package names and versions" do
      upgrades = [
        "sqlite 3.53.1 -> 3.53.2 (2.4MB)",
        "docker 29.5.2 -> 29.6.0 (9.3MB)",
        "gh 2.93.0 -> 2.95.0 (13.4MB)",
        "python@3.14 3.14.5 -> 3.14.6 (19.2MB)",
        "pnpm 11.5.1 -> 11.8.0 (4MB)",
        "usage 3.4.0 -> 3.5.2 (2.9MB)",
        "certifi 2026.5.20 -> 2026.6.17 (5.7KB)",
        "libvmaf 3.1.0 -> 3.2.0 (1.2MB)",
        "kubernetes-cli 1.36.1 -> 1.36.2 (18.2MB)",
        "jq 1.8.1 -> 1.8.2 (441KB)",
        "mise 2026.6.0 -> 2026.6.11 (34.8MB)",
        "sdl2 2.32.70 (636.8KB)",
        "opencode-desktop 1.14.48 -> 1.17.9",
        "slack 4.48.102 -> 4.50.140",
        "spotify 1.2.84.476 -> 1.2.92.148",
        "visual-studio-code 1.111.0 -> 1.125.1",
      ]

      expect(described_class.format_upgrade_summary(upgrades)).to eq([
        "certifi             2026.5.20  -> 2026.6.17 (5.7KB)",
        "docker              29.5.2     -> 29.6.0 (9.3MB)",
        "gh                  2.93.0     -> 2.95.0 (13.4MB)",
        "jq                  1.8.1      -> 1.8.2 (441KB)",
        "kubernetes-cli      1.36.1     -> 1.36.2 (18.2MB)",
        "libvmaf             3.1.0      -> 3.2.0 (1.2MB)",
        "mise                2026.6.0   -> 2026.6.11 (34.8MB)",
        "opencode-desktop    1.14.48    -> 1.17.9",
        "pnpm                11.5.1     -> 11.8.0 (4MB)",
        "python@3.14         3.14.5     -> 3.14.6 (19.2MB)",
        "sdl2                2.32.70 (636.8KB)",
        "slack               4.48.102   -> 4.50.140",
        "spotify             1.2.84.476 -> 1.2.92.148",
        "sqlite              3.53.1     -> 3.53.2 (2.4MB)",
        "usage               3.4.0      -> 3.5.2 (2.9MB)",
        "visual-studio-code  1.111.0    -> 1.125.1",
      ])
    end
  end
end
