# frozen_string_literal: true

require "bundler"
require "yaml"

RSpec.describe "Tapioca Config", type: :system do
  let(:config) { YAML.load_file(File.join(__dir__, "../../../sorbet/tapioca/config.yml")) }

  it "only excludes dependencies" do
    exclusions = config.dig("gem", "exclude")
    dependencies = Bundler::Definition.build(
      HOMEBREW_LIBRARY_PATH/"Gemfile",
      HOMEBREW_LIBRARY_PATH/"Gemfile.lock",
      false,
    ).resolve.names
    expect(exclusions - dependencies).to be_empty
  end
end
