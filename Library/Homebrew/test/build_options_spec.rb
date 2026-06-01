# typed: true
# frozen_string_literal: true

require "build_options"
require "options"

RSpec.describe BuildOptions do
  subject(:build_options) { klass.new(args, opts) }

  let(:klass) { BuildOptions }
  let(:bad_build) { klass.new(bad_args, opts) }
  let(:args) { Options.create(%w[--with-foo --with-bar --without-qux]) }
  let(:opts) { Options.create(%w[--with-foo --with-bar --without-baz --without-qux]) }
  let(:bad_args) { Options.create(%w[--with-foo --with-bar --without-bas --without-qux --without-abc]) }

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
