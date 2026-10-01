# typed: true
# frozen_string_literal: true

require "utils/profiling"

# $times is shared with wrappers installed by `inject_stats!`.
# rubocop:disable Style/GlobalVars
RSpec.describe Utils::Profiling do
  before { $times = {} }
  after { $times = nil }

  describe ".inject_stats!" do
    it "wraps matching methods with timing" do
      klass = Class.new do
        def check_something = "result"
      end

      described_class.inject_stats!(klass, /^check_/)

      expect(klass.new.check_something).to eq("result")
      expect($times).to have_key(:check_something)
    end

    it "does not recurse when a prepended module calls super" do
      klass = Class.new do
        def check_example = "base"
      end
      extension = Module.new do
        def check_example = "#{super}_extended"
      end
      klass.prepend(extension)

      described_class.inject_stats!(klass, /^check_/)

      expect(klass.new.check_example).to eq("base_extended")
      expect($times).to have_key(:check_example)
    end
  end
end
# rubocop:enable Style/GlobalVars
