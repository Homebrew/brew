# typed: true
# frozen_string_literal: true

require "dependable"

RSpec.describe Dependable do
  alias_matcher :be_a_build_dependency, :be_build

  subject(:dependable) do
    Class.new do
      include Dependable

      def initialize
        @tags = ["foo", "bar", :build]
      end
    end.new
  end

  specify do
    expect(dependable.options.as_flags.sort).to eq(%w[--foo --bar].sort)
    expect(dependable).to be_a_build_dependency
    expect(dependable).not_to be_optional
    expect(dependable).not_to be_recommended
    expect(dependable).not_to be_no_linkage
  end

  describe "with no_linkage tag" do
    subject(:dependable_no_linkage) do
      Class.new do
        include Dependable

        def initialize
          @tags = [:no_linkage]
        end
      end.new
    end

    specify do
      expect(dependable_no_linkage).to be_no_linkage
      expect(dependable_no_linkage).to be_required
    end
  end
end
