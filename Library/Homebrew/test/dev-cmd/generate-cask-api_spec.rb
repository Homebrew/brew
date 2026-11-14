# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-api"

RSpec.describe Homebrew::DevCmd::GenerateCaskApi do
  it_behaves_like "parseable arguments"

  describe "generating cask data" do
    before do
      allow(CoreCaskTap).to receive(:instance).and_return(
        instance_double(CoreCaskTap, installed?: true, name: "homebrew/cask",
                                    cask_files: [Pathname("c.rb")], cask_alias_table: { "c-alias" => "c" },
                                    cask_renames: { "c-old" => "c" }, git_head: "cask-head", tap_migrations: {}),
      )
      allow(Cask::Cask).to receive(:generating_hash!)
      cask = instance_double(Cask::Cask, token: "c")
      allow(Cask::CaskLoader).to receive(:from_path).with(Pathname("c.rb")).and_return(cask)
      allow(cask).to receive(:to_hash_with_variations)
        .and_return({ "token" => "c", "desc" => "First" }, { "token" => "c", "desc" => "Updated" })
      stub_const("OnSystem::VALID_OS_ARCH_TAGS", [])
    end

    it "regenerates cask data on every run" do
      mktmpdir.cd do
        2.times { described_class.new([]).run }

        expect(JSON.parse(Pathname("_data/cask/c.json").read).fetch("desc")).to eq("Updated")
      end
    end

    it "maps renamed and aliased tokens to their cask" do
      mktmpdir.cd do
        described_class.new([]).run

        expect(JSON.parse(Pathname("_data/cask_canonical.json").read)).to eq("c-old" => "c", "c-alias" => "c")
      end
    end
  end
end
