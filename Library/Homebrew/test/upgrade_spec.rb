# typed: strict
# frozen_string_literal: true

require "upgrade"
require "formula_installer"
require "dependency"
require "keg"
require "pkg_version"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::Upgrade do
  describe "::format_upgrade_summary" do
    it "aligns a large mixed list of package names and versions" do
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
        "sqlite              3.53.1     -> 3.53.2 (2.4MB)",
        "docker              29.5.2     -> 29.6.0 (9.3MB)",
        "gh                  2.93.0     -> 2.95.0 (13.4MB)",
        "python@3.14         3.14.5     -> 3.14.6 (19.2MB)",
        "pnpm                11.5.1     -> 11.8.0 (4MB)",
        "usage               3.4.0      -> 3.5.2 (2.9MB)",
        "certifi             2026.5.20  -> 2026.6.17 (5.7KB)",
        "libvmaf             3.1.0      -> 3.2.0 (1.2MB)",
        "kubernetes-cli      1.36.1     -> 1.36.2 (18.2MB)",
        "jq                  1.8.1      -> 1.8.2 (441KB)",
        "mise                2026.6.0   -> 2026.6.11 (34.8MB)",
        "sdl2                2.32.70 (636.8KB)",
        "opencode-desktop    1.14.48    -> 1.17.9",
        "slack               4.48.102   -> 4.50.140",
        "spotify             1.2.84.476 -> 1.2.92.148",
        "visual-studio-code  1.111.0    -> 1.125.1",
      ])
    end
  end

  describe "::upgrade_formula" do
    it "shows the version transition for an unlinked dependency installed at an older version" do
      python = formula("python@3.14") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/python-3.14.6.tgz"
      end
      kegs = ["2.7.14_2", "3.6.1", "3.6.4_4", "3.7.1"].map do |v|
        instance_double(Keg, version: PkgVersion.parse(v))
      end
      allow(python).to receive_messages(any_version_installed?: true, optlinked?: false, installed_kegs: kegs)
      dependency = instance_double(Dependency, to_formula: python)
      formula_installer = instance_double(
        FormulaInstaller, formula: Testball.new, compute_dependencies: [dependency]
      )

      expect { described_class.send(:upgrade_formula, formula_installer, dry_run: true) }
        .to output(/Would upgrade.*python@3.14 3.7.1 -> 3.14.6/m).to_stdout
    end
  end
end
