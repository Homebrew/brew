# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-internal-api"

RSpec.describe Homebrew::DevCmd::GenerateInternalApi do
  it_behaves_like "parseable arguments"

  it "writes metadata and formula executables to each generated packages file" do
    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core", formula_names: ["foo"],
                                        alias_table: {}, formula_renames: {}, git_head: "formula-head",
                                        tap_migrations: {})
    cask_tap = instance_double(CoreCaskTap, installed?: true, name: "homebrew/cask", cask_files: [Pathname("c.rb")],
                                            cask_renames: {}, git_head: "cask-head", tap_migrations: {})
    bottle_tag = Utils::Bottles::Tag.from_symbol(:arm64_sonoma)

    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(CoreCaskTap).to receive(:instance).and_return(cask_tap)
    allow(Formulary).to receive(:enable_factory_cache!)
    allow(Formula).to receive(:generating_hash!)
    allow(Cask::Cask).to receive(:generating_hash!)
    allow(Formulary).to receive(:factory).with("foo").and_return(
      instance_double(Formula, name: "foo", to_hash_with_variations: { "name" => "foo" }),
    )
    allow(Cask::CaskLoader).to receive(:load).with(Pathname("c.rb")).and_return(
      instance_double(Cask::Cask, token: "c", to_hash_with_variations: { "token" => "c" }),
    )
    allow(Homebrew::API).to receive(:download_executables_file_from_github_packages!) do |target|
      target.write "foo(1.0.0):foo-tool food\n"
      true
    end
    allow(Homebrew::API::Formula::FormulaStructGenerator).to receive(:generate_formula_struct_hash)
      .with({ "name" => "foo", "executables" => ["foo-tool", "food"] }, bottle_tag:)
      .and_return(
        instance_double(
          Homebrew::API::FormulaStruct,
          serialize: { "name" => "foo", "executables" => ["foo-tool", "food"] },
        ),
      )
    allow(Homebrew::API::Cask::CaskStructGenerator).to receive(:generate_cask_struct_hash)
      .with({ "token" => "c" }, bottle_tag:)
      .and_return(instance_double(Homebrew::API::CaskStruct, serialize: { "token" => "c" }))
    allow(Time).to receive(:now).and_return(Time.at(1_714_056_000))
    stub_const("HOMEBREW_VERSION", "4.2.18")
    stub_const("OnSystem::VALID_OS_ARCH_TAGS", [bottle_tag])

    mktmpdir do |path|
      path.cd { described_class.new([]).run }

      json = JSON.parse((path/"api/internal/packages.arm64_sonoma.json").read)
      expect(json["metadata"]).to eq({
        "homebrew_version" => "4.2.18",
        "bottle_tag"       => "arm64_sonoma",
        "generated_at"     => 1_714_056_000,
      })
      expect(json.dig("formulae", "foo", "executables")).to eq(["foo-tool", "food"])
    end
  end
end
