begin
  require 'power_assert'
rescue LoadError, SyntaxError
end

module Test
  module Unit
    module Util
      module BacktraceFilter
        TESTUNIT_FILE_SEPARATORS = %r{[\\/:]}
        TESTUNIT_PREFIX = __FILE__.split(TESTUNIT_FILE_SEPARATORS)[0..-3]
        TESTUNIT_RB_FILE = /\.rb\Z/

        POWERASSERT_PREFIX =
          defined?(::PowerAssert) ?
            ::PowerAssert.method(:start).source_location[0].split(TESTUNIT_FILE_SEPARATORS)[0..-2] :
            nil

        module_function
        def filter_backtrace(backtrace, prefix=nil)
          return ["No backtrace"] unless backtrace
          return backtrace if ENV["TEST_UNIT_ALL_BACKTRACE"]

          if prefix
            split_prefixes = [prefix.split(TESTUNIT_FILE_SEPARATORS)]
          else
            split_prefixes = [TESTUNIT_PREFIX, POWERASSERT_PREFIX].compact
          end
          test_unit_internal_p = lambda do |entry|
            components = entry.split(TESTUNIT_FILE_SEPARATORS)
            split_prefixes.any? do |split_prefix|
              split_entry = components[0, split_prefix.size]
              next false unless split_entry[0..-2] == split_prefix[0..-2]
              split_entry[-1].sub(TESTUNIT_RB_FILE, '') == split_prefix[-1]
            end
          end

          in_user_code = false
          new_backtrace = backtrace.reverse.reject do |entry|
            if test_unit_internal_p.call(entry)
              in_user_code = true
              true
            else
              not in_user_code
            end
          end.reverse

          if new_backtrace.empty?
            new_backtrace = backtrace.reject do |entry|
              test_unit_internal_p.call(entry)
            end
            new_backtrace = backtrace if new_backtrace.empty?
          end
          new_backtrace
        end
      end
    end
  end
end
