# typed: true
# frozen_string_literal: true

require "bundler"
require "tapioca/dsl"

# Tapioca's CLI applies this through its RBS rewriter before loading custom compilers.
Tapioca::Dsl::Compiler.extend(T::Generic)

require "sorbet/tapioca/compilers/cask/config"
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

  describe Tapioca::Compilers::CaskConfig do
    before do
      allow(Cask::Config).to receive(:defaults).and_return(
        languages:   [],
        appdir:      "~/.config/apps",
        appimagedir: "~/Applications",
        flatpakdir:  "~/.local/share/flatpak",
      )
    end

    it "includes accessors for default directories from other platforms" do
      file = RBI::File.new(strictness: "strong")
      pipeline = Tapioca::Dsl::Pipeline.new(
        requested_constants: [],
        requested_compilers: [described_class],
      )
      described_class.new(pipeline, file.root, Cask::Config).decorate

      output = Tapioca::DEFAULT_RBI_FORMATTER.print_file(file)
      expect(output).to include("def input_methoddir; end")
      expect(output).not_to include("def flatpakdir; end")
    end
  end
end
