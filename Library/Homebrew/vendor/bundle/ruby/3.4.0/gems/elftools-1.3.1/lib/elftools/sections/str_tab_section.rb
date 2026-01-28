# frozen_string_literal: true

require 'elftools/sections/section'
require 'elftools/util'

module ELFTools
  module Sections
    # Class of string table section.
    # Usually for section .strtab and .dynstr,
    # which record names.
    class StrTabSection < Section
      # Return the section or symbol name.
      # @param [Integer] offset
      #   Usually from +shdr.sh_name+ or +sym.st_name+.
      # @return [String] The name without null bytes.
      def name_at(offset)
        Util.cstring(stream, header.sh_offset + offset)
      end
    end
  end
end
