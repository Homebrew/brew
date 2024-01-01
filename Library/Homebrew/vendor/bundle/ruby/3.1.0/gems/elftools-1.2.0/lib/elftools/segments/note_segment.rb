# frozen_string_literal: true

require 'elftools/note'
require 'elftools/segments/segment'

module ELFTools
  module Segments
    # Class of note segment.
    class NoteSegment < Segment
      # Load note related methods.
      include ELFTools::Note

      # Address offset of notes start.
      # @return [Integer] The offset.
      def note_start
        header.p_offset
      end

      # The total size of notes in this segment.
      # @return [Integer] The size.
      def note_total_size
        header.p_filesz
      end
    end
  end
end
