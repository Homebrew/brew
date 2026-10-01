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

      # Returns the lowest virtual address backed by this segment's file content.
      #
      # A segment is mapped from an aligned boundary, so the addresses preceding
      # {#mem_head} within the same alignment unit are backed by this segment as
      # well. The bound is clamped to the address of the first byte of the file,
      # so that a malformed ELF, whose +p_offset+ and +p_vaddr+ are not congruent
      # modulo +p_align+, cannot be converted into a negative file offset.
      # @return [Integer]
      #   The vma.
      def mapped_head
        [header.p_vaddr.to_i & -header.p_align.to_i, mem_head - file_head].max
      end

      # Returns the end virtual address backed by this segment's file content.
      #
      # Addresses in between this and {#mem_tail} occupy memory but have no
      # content in file, therefore cannot be converted into a file offset.
      # @return [Integer]
      #   The vma.
      def mapped_tail
        mem_head + size
      end

      # Query if the given file offset located in this segment.
      # @param [Integer] offset
      #   File offset.
      # @param [Integer] size
      #   Size.
      # @return [Boolean]
      def offset_in?(offset, size = 0)
        file_head <= offset && offset + size <= file_tail
      end

      # Convert file offset into virtual memory address.
      #
      # The conversion is a shift by a constant, so it holds no matter +p_offset+
      # is aligned with +p_vaddr+ or not.
      # @param [Integer] offset
      #   File offset.
      # @return [Integer]
      def offset_to_vma(offset)
        offset - file_head + header.p_vaddr
      end

      # Query if the given virtual memory address is backed by this segment's
      # file content.
      #
      # Only addresses in between {#mapped_head} and {#mapped_tail} can be
      # converted into a file offset, see {#vma_to_offset}.
      # @param [Integer] vma
      #   Virtual memory address.
      # @param [Integer] size
      #   Size.
      # @return [Boolean]
      def vma_in?(vma, size = 0)
        vma >= mapped_head && vma + size <= mapped_tail
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
