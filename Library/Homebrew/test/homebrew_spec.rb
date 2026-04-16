# typed: false
# frozen_string_literal: true

require "homebrew"

# $times is the global used by inject_dump_stats! for recording method timings
# rubocop:disable Style/GlobalVars
RSpec.describe Homebrew do
  describe ".inject_dump_stats!" do
    before do
      $times = {}
    end

    after do
      $times = nil
    end

    it "wraps matching methods with timing" do
      klass = Class.new do
        def check_something
          "result"
        end
      end

      described_class.inject_dump_stats!(klass, /^check_/)

      expect(klass.new.check_something).to eq("result")
      expect($times).to have_key(:check_something)
    end

    it "does not recurse when a prepended module calls super" do
      klass = Class.new do
        def check_example
          "base"
        end
      end

      mod = Module.new do
        def check_example
          "#{super}_extended"
        end
      end

      klass.prepend(mod)
      described_class.inject_dump_stats!(klass, /^check_/)

      expect(klass.new.check_example).to eq("base_extended")
      expect($times).to have_key(:check_example)
    end

    it "only wraps methods matching the pattern" do
      klass = Class.new do
        def check_matched
          "matched"
        end

        def other_method
          "other"
        end
      end

      described_class.inject_dump_stats!(klass, /^check_/)

      instance = klass.new
      instance.check_matched
      instance.other_method

      expect($times).to have_key(:check_matched)
      expect($times).not_to have_key(:other_method)
    end
  end
end
# rubocop:enable Style/GlobalVars
