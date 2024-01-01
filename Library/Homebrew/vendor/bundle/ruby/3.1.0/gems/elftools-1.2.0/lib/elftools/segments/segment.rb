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
      def initialize(header, stream, offset_from_vma: nil)
        @header = header
        @stream = stream
        @offset_from_vma = offset_from_vma
      end

      # Return +header.p_type+ in a simplier way.
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
      # @return [Boolean] Ture or false.
      def readable?
        (header.p_flags & 4) == 4
      end

      # Is this segment writable?
      # @return [Boolean] Ture or false.
      def writable?
        (header.p_flags & 2) == 2
      end

      # Is this segment executable?
      # @return [Boolean] Ture or false.
      def executable?
        (header.p_flags & 1) == 1
      end
    end
  end
end
