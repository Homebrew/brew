# frozen_string_literal: true

# Require this file to load all segment classes.

require 'elftools/segments/segment'

require 'elftools/segments/dynamic_segment'
require 'elftools/segments/interp_segment'
require 'elftools/segments/load_segment'
require 'elftools/segments/note_segment'

module ELFTools
  # Module for defining different types of segments.
  module Segments
    # Class methods of {Segments::Segment}.
    class << Segment
      # Use different class according to +header.p_type+.
      # @param [ELFTools::Structs::ELF32_Phdr, ELFTools::Structs::ELF64_Phdr] header Program header of a segment.
      # @param [#pos=, #read] stream Streaming object.
      # @return [ELFTools::Segments::Segment]
      #   Return object dependes on +header.p_type+.
      def create(header, stream, *args, **kwargs)
        klass = case header.p_type
                when Constants::PT_DYNAMIC then DynamicSegment
                when Constants::PT_INTERP then InterpSegment
                when Constants::PT_LOAD then LoadSegment
                when Constants::PT_NOTE then NoteSegment
                else Segment
                end
        klass.new(header, stream, *args, **kwargs)
      end
    end
  end
end
