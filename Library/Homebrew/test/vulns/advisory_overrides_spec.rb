# typed: strict
# frozen_string_literal: true

require "vulns/advisory_overrides"

RSpec.describe Homebrew::Vulns::AdvisoryOverrides do
  it "protects a Homebrew range independently of upstream range corrections" do
    overrides = described_class.new({
      "requests" => { "advisories" => {
        "CVE-1" => { "preserve_homebrew_ranges" => true },
      } },
    })

    expect(overrides.preserve_homebrew_ranges?("requests", ["GHSA-1", "CVE-1"])).to be true
  end

  it "checks every alias for a protected range" do
    overrides = described_class.new({
      "requests" => { "advisories" => {
        "GHSA-1" => { "range_state" => "fixed" },
        "CVE-1"  => { "preserve_homebrew_ranges" => true },
      } },
    })

    expect(overrides.preserve_homebrew_ranges?("requests", ["GHSA-1", "CVE-1"])).to be true
  end

  it "does not apply a range protection to another formula or advisory" do
    overrides = described_class.new({
      "requests" => { "advisories" => {
        "CVE-1" => { "preserve_homebrew_ranges" => true },
      } },
    })

    expect([
      overrides.preserve_homebrew_ranges?("requests", ["CVE-2"]),
      overrides.preserve_homebrew_ranges?("other", ["CVE-1"]),
    ]).to eq [false, false]
  end

  it "rejects a non-boolean range protection" do
    data = { "requests" => { "advisories" => {
      "CVE-1" => { "preserve_homebrew_ranges" => "true" },
    } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /preserve_homebrew_ranges must be true or false/)
  end

  it "rejects a false range protection as the only override" do
    data = { "requests" => { "advisories" => {
      "CVE-1" => { "preserve_homebrew_ranges" => false },
    } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /must override at least one field/)
  end

  it "allows a false range protection alongside an upstream correction" do
    overrides = described_class.new({
      "requests" => { "advisories" => {
        "CVE-1" => { "preserve_homebrew_ranges" => false, "range_state" => "fixed" },
      } },
    })

    expect(overrides.advisory_override("requests", ["CVE-1"]))
      .to have_attributes(state: :fixed, fixed_in_overridden: false)
  end

  it "loads an explicit primary registry package identity" do
    overrides = described_class.new({
      "pnpm" => { "registry_package" => {
        "ecosystem" => "npm",
        "name"      => "pnpm",
      } },
    })

    expect(overrides.registry_package_override("pnpm"))
      .to have_attributes(ecosystem: "npm", name: "pnpm")
  end

  it "rejects unknown registry package fields" do
    data = { "pnpm" => { "registry_package" => {
      "ecosystem" => "npm",
      "name"      => "pnpm",
      "purl"      => "pkg:npm/pnpm",
    } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /unknown key.*purl/)
  end

  it "rejects missing registry package fields" do
    data = { "pnpm" => { "registry_package" => { "ecosystem" => "npm" } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /missing key.*name/)
  end

  it "rejects unsupported registry package ecosystems" do
    data = { "pnpm" => { "registry_package" => { "ecosystem" => "GIT", "name" => "pnpm" } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /supported registry package/)
  end

  it "rejects blank registry package fields" do
    data = { "pnpm" => { "registry_package" => { "ecosystem" => "npm", "name" => " \n" } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /name must be a non-blank string/)
  end

  it "rejects non-string registry package fields" do
    data = { "pnpm" => { "registry_package" => { "ecosystem" => "npm", "name" => 12 } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /name must be a non-blank string/)
  end

  it "rejects a non-mapping registry package" do
    data = { "pnpm" => { "registry_package" => "npm/pnpm" } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /registry_package must be a mapping/)
  end

  it "loads formula skips and candidate-specific state and fix corrections" do
    overrides = described_class.new({
      "linux-headers" => { "skip" => true },
      "safety"        => { "advisories" => {
        "CVE-2026-81726" => { "range_state" => "affected", "upstream_fixed_in" => nil },
      } },
    })

    expect(overrides.skip_formula?("linux-headers")).to be true
    expect(overrides.skip_formula?("safety")).to be false
    entry = overrides.advisory_override("safety", ["PYSEC-2026-1", "CVE-2026-81726"])
    expect(entry).to have_attributes(state: :affected, fixed_in: nil, fixed_in_overridden: true)
  end

  it "rejects unknown fields so misspelled corrections do not silently fail" do
    data = { "safety" => { "advisories" => {
      "CVE-2026-81726" => { "range_status" => "affected" },
    } } }

    expect { described_class.new(data) }
      .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /unknown key.*range_status/)
  end

  it "rejects a non-mapping root instead of disabling every override" do
    ["false\n", "", "---\n"].each do |yaml|
      Tempfile.create(["advisory-overrides", ".yml"]) do |file|
        file.write(yaml)
        file.flush
        expect { described_class.from_file(Pathname(file.path)) }
          .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error, /top level must be a mapping/)
      end
    end
  end

  it "rejects YAML aliases and tagged objects" do
    [
      "shared: &shared\n  skip: true\ncopy: *shared\n",
      "--- !ruby/object:Object {}\n",
    ].each do |yaml|
      Tempfile.create(["advisory-overrides", ".yml"]) do |file|
        file.write(yaml)
        file.flush
        expect { described_class.from_file(Pathname(file.path)) }
          .to raise_error(Homebrew::Vulns::AdvisoryOverrides::Error)
      end
    end
  end
end
