# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/collector'

module Test
  module Unit
    module Collector
      class ObjectSpace
        include Collector

        NAME = 'collected from the ObjectSpace'

        def initialize(source=::ObjectSpace)
          super()
          @source = source
        end

        def collect(name=NAME)
          suite = TestSuite.new(name)
          sub_suites = []
          @source.each_object(Class) do |klass|
            if(Test::Unit::TestCase > klass)
              add_suite(sub_suites, klass.suite)
            end
          end
          sort(sub_suites).each{|s| suite << s}
          adjust_ractor_tests(suite)
          suite
        end
      end
    end
  end
end
