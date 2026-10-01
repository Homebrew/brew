# frozen_string_literal: true

require 'elftools/util'

module ELFTools
  module Dynamic
    # The names a file records, which the tags point at rather than a section.
    #
    # Answers what {ELFTools::Sections::StrTabSection} answers, so that what is
    # read from the tags names itself the way what is read from the sections
    # does.
    class StringTable
      # Instantiate a {ELFTools::Dynamic::StringTable} object.
      # @param [#pos=, #read] stream Streaming object.
      # @param [Method] offset
      #   Call this method to get the file offset the table starts at.
      def initialize(stream, offset)
        @stream = stream
        @offset = offset
      end

      # Return the name recorded at an offset into the table.
      # @param [Integer] offset Usually from +tag.d_val+ or +sym.st_name+.
      # @return [String] The name without null bytes.
      def name_at(offset)
        Util.cstring(@stream, @offset.call + offset)
      end
    end
  end
end
