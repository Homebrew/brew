# frozen_string_literal: true

require "build_options"
require "options"

RSpec.describe BuildOptions do
  alias_matcher :be_built_with, :be_with
  alias_matcher :be_built_without, :be_without

  subject(:build_options) { described_class.new(args, opts) }

  let(:bad_build) { described_class.new(bad_args, opts) }
  let(:args) { Options.create(%w[--with-foo --with-bar --without-qux]) }
  let(:opts) { Options.create(%w[--with-foo --with-bar --without-baz --without-qux]) }
  let(:bad_args) { Options.create(%w[--with-foo --with-bar --without-bas --without-qux --without-abc]) }

  specify "#with?" do
    expect(build_options).to be_built_with("foo")
    expect(build_options).to be_built_with("bar")
    expect(build_options).to be_built_with("baz")
  end

  specify "#without?" do
    expect(build_options).to be_built_without("qux")
    expect(build_options).to be_built_without("xyz")
  end

  specify "#used_options" do
    expect(build_options.used_options).to include("--with-foo")
    expect(build_options.used_options).to include("--with-bar")
  end

  specify "#unused_options" do
    expect(build_options.unused_options).to include("--without-baz")
  end
end
