# frozen_string_literal: true

require 'elftools/constants'
module ELFTools
  module Sections
    # Base class of sections.
    class Section
      attr_reader :header # @return [ELFTools::Structs::ELF_Shdr] Section header.
      attr_reader :stream # @return [#pos=, #read] Streaming object.

      # Instantiate a {Section} object.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   The section header object.
      # @param [#pos=, #read] stream
      #   The streaming object for further dump.
      # @param [ELFTools::Sections::StrTabSection, Proc] section_name_table
      #   The string table object. For fetching section names.
      #   If +Proc+ if given, it will call at the first
      #   time access +#name+.
      # @param [Method] offset_from_vma
      #   The method to get offset of file, given virtual memory address.
      def initialize(header, stream, offset_from_vma: nil, section_name_table: nil, **_kwargs)
        @header = header
        @stream = stream
        @section_name_table = section_name_table
        @offset_from_vma = offset_from_vma
      end

      # Return +header.sh_type+ in a simpler way.
      # @return [Integer]
      #   The type, meaning of types are defined in {Constants::SHT}.
      def type
        header.sh_type.to_i
      end

      # Get name of this section.
      # @return [String] The name.
      def name
        @name ||= @section_name_table.call.name_at(header.sh_name)
      end

      # Fetch data of this section.
      # @return [String] Data.
      def data
        stream.pos = header.sh_offset
        stream.read(header.sh_size)
      end

      # Is this section written to while the file runs?
      # @return [Boolean] True or false.
      # @example
      #   elf.section_by_name('.data').writable?
      #   #=> true
      def writable?
        header.sh_flags.allbits?(Constants::SHF_WRITE)
      end

      # Is this section executed?
      # @return [Boolean] True or false.
      # @example
      #   elf.section_by_name('.text').executable?
      #   #=> true
      def executable?
        header.sh_flags.allbits?(Constants::SHF_EXECINSTR)
      end

      # Does this section take memory while the file runs?
      #
      # The ones that do are what a file is loaded by, the rest being what is
      # recorded about it, its symbol names and its debugging information
      # among them.
      # @return [Boolean] True or false.
      # @example
      #   elf.section_by_name('.symtab').allocated?
      #   #=> false
      def allocated?
        header.sh_flags.allbits?(Constants::SHF_ALLOC)
      end

      # Is this a null section?
      # @return [Boolean] No it's not.
      def null?
        false
      end
    end
  end
end
