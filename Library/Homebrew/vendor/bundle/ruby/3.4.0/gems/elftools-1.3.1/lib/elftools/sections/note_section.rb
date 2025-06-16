# frozen_string_literal: true

require 'elftools/note'
require 'elftools/sections/section'

module ELFTools
  module Sections
    # Class of note section.
    # Note section records notes
    class NoteSection < Section
      # Load note related methods.
      include ELFTools::Note

      # Address offset of notes start.
      # @return [Integer] The offset.
      def note_start
        header.sh_offset
      end

      # The total size of notes in this section.
      # @return [Integer] The size.
      def note_total_size
        header.sh_size
      end
    end
  end
end
