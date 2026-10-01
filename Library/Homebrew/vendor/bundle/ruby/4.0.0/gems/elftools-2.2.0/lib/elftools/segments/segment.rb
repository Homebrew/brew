# frozen_string_literal: true

module ELFTools
  module Segments
    # Base class of segments.
    class Segment
      attr_reader :header # @return [ELFTools::Structs::ELF32_Phdr, ELFTools::Structs::ELF64_Phdr] Program header.
      attr_reader :stream # @return [#pos=, #read] Streaming object.

      # Instantiate a {Segment} object.
      # @param [ELFTools::Structs::ELF32_Phdr, ELFTools::Structs::ELF64_Phdr] header
      #   Program header.
      # @param [#pos=, #read] stream
      #   Streaming object.
      # @param [Method] offset_from_vma
      #   The method to get offset of file, given virtual memory address.
      # @param [Integer] machine
      #   The machine of the ELF file, which decides what the entries a
      #   segment points at mean. This should be +e_machine+ of the ELF header.
      def initialize(header, stream, offset_from_vma: nil, machine: nil, **_kwargs)
        @header = header
        @stream = stream
        @offset_from_vma = offset_from_vma
        @machine = machine
      end

      # Return +header.p_type+ in a simpler way.
      # @return [Integer]
      #   The type, meaning of types are defined in {Constants::PT}.
      def type
        header.p_type
      end

      # The content in this segment.
      # @return [String] The content.
      def data
        stream.pos = header.p_offset
        stream.read(header.p_filesz)
      end

      # Is this segment readable?
      # @return [Boolean] True or false.
      def readable?
        header.p_flags.allbits?(4)
      end

      # Is this segment writable?
      # @return [Boolean] True or false.
      def writable?
        header.p_flags.allbits?(2)
      end

      # Is this segment executable?
      # @return [Boolean] True or false.
      def executable?
        header.p_flags.allbits?(1)
      end
    end
  end
end
