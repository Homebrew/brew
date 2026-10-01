# frozen_string_literal: true

require 'elftools/relative_relocations'
require 'elftools/sections/section'

module ELFTools
  module Sections
    # Class of the section packing the relocations that only add the load bias.
    #
    # This section is usually named .relr.dyn, and records the very relocations
    # the +DT_RELR+ tag points at.
    class RelativeRelocationSection < Section
      # Instantiate a {RelativeRelocationSection} object.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   See {Section#initialize} for more information.
      # @param [#pos=, #read] stream
      #   See {Section#initialize} for more information.
      # @param [Integer] machine
      #   The machine of the ELF file, which decides what these relocations
      #   are of. This should be +e_machine+ of the ELF header.
      def initialize(header, stream, machine: nil, **_kwargs)
        @machine = machine
        super
      end

      # The relocations the section packs.
      # @return [Array<ELFTools::Relocation>]
      #   The relocations, in the ascending order the section records them.
      # @example
      #   section.relocations.map(&:type_name).uniq
      #   #=> ['R_X86_64_RELATIVE']
      def relocations
        @relocations ||= RelativeRelocations.new(
          stream, header.sh_offset.to_i...(header.sh_offset.to_i + header.sh_size.to_i),
          elf_class: header.elf_class, endian: header.class.self_endian, machine: @machine
        ).to_a
      end

      # How many relocations the section packs.
      # @return [Integer] The number.
      def num_relocations
        relocations.size
      end
    end
  end
end
