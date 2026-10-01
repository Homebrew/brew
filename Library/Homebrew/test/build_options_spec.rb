# typed: true
# frozen_string_literal: true

require "build_options"
require "options"

RSpec.describe BuildOptions do
  subject(:build_options) { described_class.new(args, opts) }

  let(:args) { Options.create(%w[--with-foo --with-bar --without-qux]) }
  let(:opts) { Options.create(%w[--with-foo --with-bar --without-baz --without-qux]) }

  alias_matcher :be_built_with, :be_with
  alias_matcher :be_built_without, :be_without

  specify do
    expect(build_options).to be_built_with("foo")
    expect(build_options).to be_built_with("bar")
    expect(build_options).to be_built_with("baz")
    expect(build_options).to be_built_without("qux")
    expect(build_options).to be_built_without("xyz")
    expect(build_options.used_options).to include("--with-foo")
    expect(build_options.used_options).to include("--with-bar")
    expect(build_options.unused_options).to include("--without-baz")
  end
end
