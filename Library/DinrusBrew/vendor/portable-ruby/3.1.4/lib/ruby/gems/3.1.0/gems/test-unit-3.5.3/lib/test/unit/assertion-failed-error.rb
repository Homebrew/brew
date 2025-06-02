#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # Thrown by Test::Unit::Assertions when an assertion fails.
    class AssertionFailedError < StandardError
      @debug_on_failure = false
      class << self
        def debug_on_failure=(boolean)
          @debug_on_failure = boolean
        end

        def debug_on_failure?
          @debug_on_failure
        end
      end

      attr_accessor :expected, :actual, :user_message
      attr_accessor :inspected_expected, :inspected_actual
      def initialize(message=nil, options=nil)
        options ||= {}
        @expected = options[:expected]
        @actual = options[:actual]
        @inspected_expected = options[:inspected_expected]
        @inspected_actual = options[:inspected_actual]
        @user_message = options[:user_message]
        super(message)
        debug_on_failure
      end

      private
      def debug_on_failure
        return unless self.class.debug_on_failure?

        begin
          require "debug"
        rescue LoadError
          return
        end

        return unless binding.respond_to?(:break)

        frames = caller(0)
        pre = nil
        Util::BacktraceFilter.filter_backtrace(frames).each do |location|
          frame_index = frames.index(location)
          next if frame_index.nil?
          pre = "frame #{frame_index}"
          break
        end
        binding.break(pre: pre)
      end
    end
  end
end
