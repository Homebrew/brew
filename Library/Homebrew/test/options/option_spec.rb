# frozen_string_literal: true

require "options"

describe Option do
  subject(:option) { described_class.new("foo") }

  specify "#to_s" do
    expect(option.to_s).to eq("--foo")
  end

  specify "equality" do
    foo = described_class.new("foo")
    bar = described_class.new("bar")
    expect(option).to eq(foo)
    expect(option).not_to eq(bar)
    expect(option).to eql(foo)
    expect(option).not_to eql(bar)
  end

  specify "#description" do
    expect(option.description).to be_empty
    expect(described_class.new("foo", "foo").description).to eq("foo")
  end

  specify "#inspect" do
    expect(option.inspect).to eq("#<Option: \"--foo\">")
  end
end
