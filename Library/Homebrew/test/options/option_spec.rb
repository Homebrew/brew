# typed: true
# frozen_string_literal: true

require "options"

RSpec.describe Option do
  subject(:option) { described_class.new("foo") }

  specify do
    expect(option.to_s).to eq("--foo")
    expect(option.description).to be_empty
    expect(described_class.new("foo", "foo").description).to eq("foo")
    expect(option.inspect).to eq("#<Option: \"--foo\">")
  end

  specify "equality" do
    foo = described_class.new("foo")
    bar = described_class.new("bar")
    expect(option).to eq(foo)
    expect(option).not_to eq(bar)
    expect(option).to eql(foo)
    expect(option).not_to eql(bar)
  end
end
