# typed: strict
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

RSpec.describe RuboCop::Cop::HelperFunctions do
  it "caches descendant send nodes for the current source" do
    processed_source = RuboCop::ProcessedSource.new("class Foo; bar; end", RuboCop::TargetRuby::DEFAULT_VERSION)
    node = processed_source.ast
    raise "Failed to parse source" unless node

    first = described_class.descendant_send_nodes(processed_source, node)
    again = described_class.descendant_send_nodes(processed_source, node)

    other_source = RuboCop::ProcessedSource.new("class Foo; baz; end", RuboCop::TargetRuby::DEFAULT_VERSION)
    other_node = other_source.ast
    raise "Failed to parse source" unless other_node

    expect([first.equal?(again), first.equal?(described_class.descendant_send_nodes(other_source, other_node))])
      .to eq([true, false])
  end
end
