# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-api"

RSpec.describe Homebrew::DevCmd::GenerateCaskApi do
  it_behaves_like "parseable arguments"

  it "regenerates cask data on every run" do
    allow(CoreCaskTap).to receive(:instance).and_return(
      instance_double(CoreCaskTap, installed?: true, name: "homebrew/cask",
                                  cask_files: [Pathname("c.rb")], cask_renames: {}, git_head: "cask-head",
                                  tap_migrations: {}),
    )
    allow(Cask::Cask).to receive(:generating_hash!)
    cask = instance_double(Cask::Cask, token: "c")
    allow(Cask::CaskLoader).to receive(:from_path).with(Pathname("c.rb")).and_return(cask)
    allow(cask).to receive(:to_hash_with_variations)
      .and_return({ "token" => "c", "desc" => "First" }, { "token" => "c", "desc" => "Updated" })
    stub_const("OnSystem::VALID_OS_ARCH_TAGS", [])

    mktmpdir.cd do
      2.times { described_class.new([]).run }

      expect(JSON.parse(Pathname("_data/cask/c.json").read).fetch("desc")).to eq("Updated")
    end
  end
end
