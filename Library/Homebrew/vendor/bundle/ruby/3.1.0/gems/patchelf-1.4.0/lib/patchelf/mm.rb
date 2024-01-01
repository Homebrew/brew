# frozen_string_literal: true

require 'patchelf/helper'

module PatchELF
  # Memory management, provides malloc/free to allocate LOAD segments.
  # @private
  class MM
    attr_reader :extend_size # @return [Integer] The size extended.
    attr_reader :threshold # @return [Integer] Where the file start to be extended.

    # Instantiate a {MM} object.
    # @param [ELFTools::ELFFile] elf
    def initialize(elf)
      @elf = elf
      @request = []
    end

    # @param [Integer] size
    # @return [void]
    # @yieldparam [Integer] off
    # @yieldparam [Integer] vaddr
    # @yieldreturn [void]
    #   One can only do the following things in the block:
    #   1. Set ELF headers' attributes (with ELFTools)
    #   2. Invoke {Saver#inline_patch}
    def malloc(size, &block)
      raise ArgumentError, 'malloc\'s size most be positive.' if size <= 0

      @request << [size, block]
    end

    # Let the malloc / free requests be effective.
    # @return [void]
    def dispatch!
      return if @request.empty?

      @request_size = @request.map(&:first).inject(0, :+)
      # The malloc-ed area must be 'rw-' since the dynamic table will be modified during runtime.
      # Find all LOADs and calculate their f-gaps and m-gaps.
      # We prefer f-gap since it doesn't need move the whole binaries.
      # 1. Find if any f-gap has enough size, and one of the LOAD next to it is 'rw-'.
      #   - expand (forwardlly), only need to change the attribute of LOAD.
      # 2. Do 1. again but consider m-gaps instead.
      #   - expand (forwardlly), need to modify all section headers.
      # 3. We have to create a new LOAD, now we need to expand the first LOAD for putting new segment header.

      # First of all we check if there're less than two LOADs.
      abnormal_elf('No LOAD segment found, not an executable.') if load_segments.empty?
      # TODO: Handle only one LOAD. (be careful if memsz > filesz)

      fgap_method || mgap_method || new_load_method
    end

    # Query if extended.
    # @return [Boolean]
    def extended?
      defined?(@threshold)
    end

    # Get correct offset after the extension.
    #
    # @param [Integer] off
    # @return [Integer]
    #   Shifted offset.
    def extended_offset(off)
      return off unless defined?(@threshold)
      return off if off < @threshold

      off + @extend_size
    end

    private

    def fgap_method
      idx = find_gap { |prv, nxt| nxt.file_head - prv.file_tail }
      return false if idx.nil?

      loads = load_segments
      # prefer extend backwardly
      return extend_backward(loads[idx - 1]) if writable?(loads[idx - 1])

      extend_forward(loads[idx])
    end

    def extend_backward(seg, size = @request_size)
      invoke_callbacks(seg, seg.file_tail)
      seg.header.p_filesz += size
      seg.header.p_memsz += size
      true
    end

    def extend_forward(seg, size = @request_size)
      seg.header.p_offset -= size
      seg.header.p_vaddr -= size
      seg.header.p_filesz += size
      seg.header.p_memsz += size
      invoke_callbacks(seg, seg.file_head)
      true
    end

    def mgap_method
      # |  1  | |  2  |
      # |  1  |        |  2  |
      #=>
      # |  1      | |  2  |
      # |  1      |    |  2  |
      idx = find_gap(check_sz: false) { |prv, nxt| PatchELF::Helper.aligndown(nxt.mem_head) - prv.mem_tail }
      return false if idx.nil?

      loads = load_segments
      @threshold = loads[idx].file_head
      @extend_size = PatchELF::Helper.alignup(@request_size)
      shift_attributes
      # prefer backward than forward
      return extend_backward(loads[idx - 1]) if writable?(loads[idx - 1])

      # NOTE: loads[idx].file_head has been changed in shift_attributes
      extend_forward(loads[idx], @extend_size)
    end

    def find_gap(check_sz: true)
      loads = load_segments
      loads.each_with_index do |l, i|
        next if i.zero?
        next unless writable?(l) || writable?(loads[i - 1])

        sz = yield(loads[i - 1], l)
        abnormal_elf('LOAD segments are out of order.') if check_sz && sz.negative?
        next unless sz >= @request_size

        return i
      end
      nil
    end

    # TODO
    def new_load_method
      raise NotImplementedError
    end

    def writable?(seg)
      seg.readable? && seg.writable?
    end

    # For all attributes >= threshold, += offset
    def shift_attributes
      # ELFHeader->section_header
      # Sections:
      #   all
      # Segments:
      #   all
      # XXX: will be buggy if someday the number of segments can be changed.

      # Bottom-up
      @elf.each_sections do |sec|
        sec.header.sh_offset += extend_size if sec.header.sh_offset >= threshold
      end
      @elf.each_segments do |seg|
        next unless seg.header.p_offset >= threshold

        seg.header.p_offset += extend_size
        # We have to change align of LOAD segment since ld.so checks it.
        seg.header.p_align = Helper.page_size if seg.is_a?(ELFTools::Segments::LoadSegment)
      end

      @elf.header.e_shoff += extend_size if @elf.header.e_shoff >= threshold
    end

    def load_segments
      @elf.segments_by_type(:load)
    end

    def invoke_callbacks(seg, start)
      cur = start
      @request.each do |sz, block|
        block.call(cur, seg.offset_to_vma(cur))
        cur += sz
      end
    end

    def abnormal_elf(msg)
      raise ArgumentError, msg
    end
  end
end
