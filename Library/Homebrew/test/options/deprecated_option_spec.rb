# typed: true
# frozen_string_literal: true

require "options"

RSpec.describe DeprecatedOption do
  subject(:option) { described_class.new("foo", "bar") }

  specify do
    expect(option.old).to eq("foo")
    expect(option.old_flag).to eq("--foo")
    expect(option.current).to eq("bar")
    expect(option.current_flag).to eq("--bar")
  end

  specify "equality" do
    foobar = described_class.new("foo", "bar")
    boofar = described_class.new("boo", "far")
    expect(foobar).to eq(option)
    expect(option).to eq(foobar)
    expect(boofar).not_to eq(option)
    expect(option).not_to eq(boofar)
  end
end
