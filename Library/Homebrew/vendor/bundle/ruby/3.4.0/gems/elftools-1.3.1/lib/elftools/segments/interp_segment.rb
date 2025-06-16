# frozen_string_literal: true

require 'elftools/segments/segment'

module ELFTools
  module Segments
    # For DT_INTERP segment, knows how to get path of
    # ELF interpreter.
    class InterpSegment < Segment
      # Get the path of interpreter.
      # @return [String] Path to the interpreter.
      # @example
      #   interp_segment.interp_name
      #   #=> '/lib64/ld-linux-x86-64.so.2'
      def interp_name
        data[0..-2] # remove last null byte
      end
    end
  end
end
