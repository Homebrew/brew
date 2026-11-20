# typed: strict
# frozen_string_literal: true

require "bundler"
require "tapioca/dsl"

require "sorbet/tapioca/compilers/rubocop"

RSpec.describe Tapioca::Compilers::RuboCop do
  sig { returns(String) }
  subject(:rbi) do
    file = RBI::File.new(strictness: "strong")
    pipeline = Tapioca::Dsl::Pipeline.new(requested_constants: [], requested_compilers: [described_class])
    described_class.new(pipeline, file.root, RuboCop::Cop::Homebrew::NoUntypedKeywordRest).decorate
    Tapioca::DEFAULT_RBI_FORMATTER.print_file(file)
  end

  it "adds a rest parameter only to a matcher with a positional pattern argument" do
    expect(rbi).to include(
      "def untyped_param_type(node, *pattern, **kwargs, &block); end",
      "def signature?(node, **kwargs, &block); end",
    )
  end
end
