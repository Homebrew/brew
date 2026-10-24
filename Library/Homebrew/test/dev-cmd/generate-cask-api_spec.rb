# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-api"

RSpec.describe Homebrew::DevCmd::GenerateCaskApi do
  it_behaves_like "parseable arguments"

  it "generates cask data from the tap passed with `--tap`" do
    tap = instance_double(Tap, installed?: true, name: "user/repo", cask_files: [Pathname("c.rb")],
                               cask_renames: {}, git_head: "tap-head", tap_migrations: {})
    allow(Tap).to receive(:fetch).with("user/repo").and_return(tap)
    allow(Cask::Cask).to receive(:generating_hash!)
    allow(Cask::CaskLoader).to receive(:load).with(Pathname("c.rb")).and_return(
      instance_double(Cask::Cask, token: "c", to_hash_with_variations: { "token" => "c" }),
    )
    allow(Homebrew::API::Cask::CaskStructGenerator).to receive(:generate_cask_struct_hash)
      .and_return(instance_double(Homebrew::API::CaskStruct, serialize: { "token" => "c" }))
    stub_const("OnSystem::VALID_OS_ARCH_TAGS", [Utils::Bottles::Tag.from_symbol(:arm64_sonoma)])

    mktmpdir do |path|
      path.cd { described_class.new(["--tap=user/repo"]).run }

      expect(JSON.parse((path/"api/internal/cask.arm64_sonoma.json").read)["tap_git_head"]).to eq("tap-head")
    end
  end
end
