# frozen_string_literal: true

require 'elftools/dynamic'
require 'elftools/sections/section'

module ELFTools
  module Sections
    # Class for dynamic table section.
    #
    # This section should always be named .dynamic.
    # This class knows how to get the list of dynamic tags.
    class DynamicSection < Section
      include ELFTools::Dynamic

      # Instantiate a {DynamicSection} object.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   See {Section#initialize} for more information.
      # @param [#pos=, #read] stream
      #   See {Section#initialize} for more information.
      # @param [Integer] machine
      #   The machine of the ELF file, which decides what the entries a tag
      #   points at mean. This should be +e_machine+ of the ELF header.
      def initialize(header, stream, machine: nil, **_kwargs)
        @machine = machine
        super
      end

      # Get the start address of tags.
      # @return [Integer] Start address of tags.
      def tag_start
        header.sh_offset
      end
    end
  end
end
