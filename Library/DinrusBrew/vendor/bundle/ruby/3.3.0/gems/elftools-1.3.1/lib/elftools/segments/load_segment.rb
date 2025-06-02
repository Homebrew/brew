# frozen_string_literal: true

require 'elftools/segments/segment'

module ELFTools
  module Segments
    # For DT_LOAD segment.
    # Able to query between file offset and virtual memory address.
    class LoadSegment < Segment
      # Returns the start of this segment.
      # @return [Integer]
      #   The file offset.
      def file_head
        header.p_offset.to_i
      end

      # Returns size in file.
      # @return [Integer]
      #   The size.
      def size
        header.p_filesz.to_i
      end

      # Returns the end of this segment.
      # @return [Integer]
      #   The file offset.
      def file_tail
        file_head + size
      end

      # Returns the start virtual address of this segment.
      # @return [Integer]
      #   The vma.
      def mem_head
        header.p_vaddr.to_i
      end

      # Returns size in memory.
      # @return [Integer]
      #   The size.
      def mem_size
        header.p_memsz.to_i
      end

      # Returns the end virtual address of this segment.
      # @return [Integer]
      #   The vma.
      def mem_tail
        mem_head + mem_size
      end

      # Query if the given file offset located in this segment.
      # @param [Integer] offset
      #   File offset.
      # @param [Integer] size
      #   Size.
      # @return [Boolean]
      def offset_in?(offset, size = 0)
        file_head <= offset && offset + size < file_tail
      end

      # Convert file offset into virtual memory address.
      # @param [Integer] offset
      #   File offset.
      # @return [Integer]
      def offset_to_vma(offset)
        # XXX: What if file_head is not aligned with p_vaddr (which is invalid according to ELF spec)?
        offset - file_head + header.p_vaddr
      end

      # Query if the given virtual memory address located in this segment.
      # @param [Integer] vma
      #   Virtual memory address.
      # @param [Integer] size
      #   Size.
      # @return [Boolean]
      def vma_in?(vma, size = 0)
        vma >= (header.p_vaddr & -header.p_align) &&
          vma + size <= mem_tail
      end

      # Convert virtual memory address into file offset.
      # @param [Integer] vma
      #   Virtual memory address.
      # @return [Integer]
      def vma_to_offset(vma)
        vma - header.p_vaddr + header.p_offset
      end
    end
  end
end
