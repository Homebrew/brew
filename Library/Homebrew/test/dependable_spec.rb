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

  specify "#options" do
    expect(dependable.options.as_flags.sort).to eq(%w[--foo --bar].sort)
  end

  specify "#build?" do # rubocop:todo RSpec/AggregateExamples
    expect(dependable).to be_a_build_dependency
  end

  specify "#optional?" do # rubocop:todo RSpec/AggregateExamples
    expect(dependable).not_to be_optional
  end

  specify "#recommended?" do # rubocop:todo RSpec/AggregateExamples
    expect(dependable).not_to be_recommended
  end

  specify "#no_linkage?" do # rubocop:todo RSpec/AggregateExamples
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

    specify "#no_linkage?" do
      expect(dependable_no_linkage).to be_no_linkage
    end

    specify "#required?" do # rubocop:todo RSpec/AggregateExamples
      expect(dependable_no_linkage).to be_required
    end
  end
end
