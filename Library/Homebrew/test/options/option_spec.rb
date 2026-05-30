# typed: true
# frozen_string_literal: true

require "options"

RSpec.describe Option do
  subject(:option) { klass.new("foo") }

  let(:klass) { Option }

  specify do
    expect(option.to_s).to eq("--foo")
    expect(option.description).to be_empty
    expect(klass.new("foo", "foo").description).to eq("foo")
    expect(option.inspect).to eq("#<Option: \"--foo\">")
  end

  specify "equality" do
    foo = klass.new("foo")
    bar = klass.new("bar")
    expect(option).to eq(foo)
    expect(option).not_to eq(bar)
    expect(option).to eql(foo)
    expect(option).not_to eql(bar)
  end
end
