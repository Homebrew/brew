# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-formula-api"

RSpec.describe Homebrew::DevCmd::GenerateFormulaApi do
  before do
    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core", formula_names: ["foo"],
                                        alias_table: {}, formula_renames: {}, git_head: "formula-head",
                                        tap_migrations: {})
    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(Formulary).to receive(:enable_factory_cache!)
    allow(Formula).to receive(:generating_hash!)
    allow(Formulary).to receive(:factory).with("foo").and_return(
      instance_double(Formula, name: "foo", pkg_version: PkgVersion.parse("1.0.0"),
                               to_hash_with_variations: { "name" => "foo" }),
    )
    allow(Homebrew::API).to receive(:download_executables_file_from_github_packages!) do |target|
      target.write "foo(1.0.0):foo-tool food\n"
      true
    end
    allow(Homebrew::API::Formula::FormulaStructGenerator).to receive(:generate_formula_struct_hash)
      .and_return(instance_double(Homebrew::API::FormulaStruct, serialize: { "name" => "foo" }))
    stub_const("OnSystem::VALID_OS_ARCH_TAGS", [Utils::Bottles::Tag.from_symbol(:arm64_sonoma)])
  end

  it_behaves_like "parseable arguments"

  it "writes formula executables to generated formula data" do
    allow(Homebrew::Vulns::AdvisoryDatabase).to receive(:load).and_return(nil)

    Dir.mktmpdir do |tmpdir|
      path = Pathname.new(tmpdir)
      path.cd { described_class.new([]).run }

      data = JSON.parse((path/"_data/formula/foo.json").read)
      expect(data["executables"]).to eq(["foo-tool", "food"])
      expect(data).not_to have_key("vulnerabilities")
    end
  end

  context "when passed `--tap`" do
    before do
      tap = instance_double(Tap, installed?: true, name: "user/repo", formula_names: ["foo"], alias_table: {},
                                 formula_renames: {}, git_head: "tap-head", tap_migrations: {})
      allow(Tap).to receive(:fetch).with("user/repo").and_return(tap)
    end

    it "generates formula data from the tap" do
      Dir.mktmpdir do |tmpdir|
        path = Pathname.new(tmpdir)
        path.cd { described_class.new(["--tap=user/repo"]).run }

        expect(JSON.parse((path/"_data/formula/foo.json").read)["name"]).to eq("foo")
      end
    end

    it "does not download the executables database" do
      expect(Homebrew::API).not_to receive(:download_executables_file_from_github_packages!)

      Dir.mktmpdir { |tmpdir| Pathname.new(tmpdir).cd { described_class.new(["--tap=user/repo"]).run } }
    end

    it "does not load the advisory database" do
      expect(Homebrew::Vulns::AdvisoryDatabase).not_to receive(:load)

      Dir.mktmpdir { |tmpdir| Pathname.new(tmpdir).cd { described_class.new(["--tap=user/repo"]).run } }
    end
  end

  it "attaches vulnerabilities from the advisory-database corpus to the public formula JSON" do
    advisories = Homebrew::Vulns::AdvisoryDatabase.new({
      "meta"       => {},
      "advisories" => {
        "foo" => [{
          "id"       => "BREW-foo-CVE-2024-1234",
          "upstream" => ["CVE-2024-1234"],
          "affected" => [{
            "package"            => { "ecosystem" => "Homebrew", "name" => "foo" },
            "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
            "ecosystem_specific" => { "fix" => nil },
          }],
        }],
      },
    })
    allow(Homebrew::Vulns::AdvisoryDatabase).to receive(:load).and_return(advisories)

    Dir.mktmpdir do |tmpdir|
      path = Pathname.new(tmpdir)
      path.cd { described_class.new([]).run }

      vulns = JSON.parse((path/"_data/formula/foo.json").read)["vulnerabilities"]
      expect(vulns["open"].map { |e| e["id"] }).to eq ["BREW-foo-CVE-2024-1234"]
      expect(vulns["patched"]).to eq []
      expect(vulns["fixed_count"]).to eq 0
    end
  end

  it "omits the vulnerabilities field and warns when the advisory feed cannot be loaded" do
    allow(Homebrew::Vulns::AdvisoryDatabase).to receive(:load)
      .and_raise(Homebrew::Vulns::CachedFeed::Error, "boom")

    Dir.mktmpdir do |tmpdir|
      path = Pathname.new(tmpdir)
      expect { path.cd { described_class.new([]).run } }
        .to output(/Skipping vulnerabilities field: boom/).to_stderr
      expect(JSON.parse((path/"_data/formula/foo.json").read)).not_to have_key("vulnerabilities")
    end
  end
end
