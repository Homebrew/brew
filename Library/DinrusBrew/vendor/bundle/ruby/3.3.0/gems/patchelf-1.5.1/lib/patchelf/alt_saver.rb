# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/elf_file'
require 'elftools/structs'
require 'elftools/util'
require 'fileutils'

require 'patchelf/helper'

# :nodoc:
module PatchELF
  # TODO: refactor buf_* methods here
  # TODO: move all refinements into a separate file / helper file.
  # refinements for cleaner syntax / speed / memory optimizations
  module Refinements
    refine StringIO do
      # behaves like C memset. Equivalent to calling stream.write(char * nbytes)
      # the benefit of preferring this over `stream.write(char * nbytes)` is only when data to be written is large.
      # @param [String] char
      # @param [Integer] nbytes
      # @return[void]
      def fill(char, nbytes)
        at_once = Helper.page_size
        pending = nbytes

        if pending > at_once
          to_write = char * at_once
          while pending >= at_once
            write(to_write)
            pending -= at_once
          end
        end
        write(char * pending) if pending.positive?
      end
    end
  end
  using Refinements

  # Internal use only.
  # alternative to +Saver+, that aims to be byte to byte equivalent with NixOS/patchelf.
  #
  # *DISCLAIMER*: This differs from +Saver+ in number of ways.  No lazy reading,
  # inconsistent use of existing internal API(e.g: manual reading of data instead of calling +section.data+)
  # @private
  class AltSaver
    attr_reader :in_file # @return [String] Input filename.
    attr_reader :out_file # @return [String] Output filename.

    # Instantiate a {AltSaver} object.
    # the params passed are the same as the ones passed to +Saver+
    # @param [String] in_file
    # @param [String] out_file
    # @param [{Symbol => String, Array}] set
    def initialize(in_file, out_file, set)
      @in_file = in_file
      @out_file = out_file
      @set = set

      f = File.open(in_file, 'rb')
      # the +@buffer+ and +@elf+ both could work on same +StringIO+ stream,
      # the updating of @buffer in place blocks us from looking up old values.
      # TODO: cache the values needed later, use same stream for +@buffer+ and +@elf+.
      # also be sure to update the stream offset passed to Segments::Segment.
      @elf = ELFTools::ELFFile.new(f)
      @buffer = StringIO.new(f.tap(&:rewind).read) # StringIO makes easier to work with Bindata

      @ehdr = @elf.header
      @endian = @elf.endian
      @elf_class = @elf.elf_class

      @segments = @elf.segments # usage similar to phdrs
      @sections = @elf.sections # usage similar to shdrs
      update_section_idx!

      # {String => String}
      # section name to its data mapping
      @replaced_sections = {}
      @section_alignment = ehdr.e_phoff.num_bytes

      # using the same environment flag as patchelf, makes it easier for debugging
      Logger.level = ::Logger.const_get(ENV['PATCHELF_DEBUG'] ? :DEBUG : :WARN)
    end

    # @return [void]
    def save!
      @set.each { |mtd, val| send(:"modify_#{mtd}") if val }
      rewrite_sections

      FileUtils.cp(in_file, out_file) if out_file != in_file
      patch_out
      # Let output file have the same permission as input.
      FileUtils.chmod(File.stat(in_file).mode, out_file)
    end

    private

    attr_reader :ehdr, :endian, :elf_class

    def old_sections
      @old_sections ||= @elf.sections
    end

    def buf_cstr(off)
      cstr = []
      with_buf_at(off) do |buf|
        loop do
          c = buf.read 1
          break if c.nil? || c == "\x00"

          cstr.push c
        end
      end
      cstr.join
    end

    def buf_move!(dst_idx, src_idx, n_bytes)
      with_buf_at(src_idx) do |buf|
        to_write = buf.read(n_bytes)
        buf.seek dst_idx
        buf.write to_write
      end
    end

    def dynstr
      find_section '.dynstr'
    end

    # yields dynamic tag, and offset in buffer
    def each_dynamic_tags
      return unless block_given?

      sec = find_section '.dynamic'
      return unless sec

      return if sec.header.sh_type == ELFTools::Constants::SHT_NOBITS

      shdr = sec.header
      with_buf_at(shdr.sh_offset) do |buf|
        dyn = ELFTools::Structs::ELF_Dyn.new(elf_class: elf_class, endian: endian)
        loop do
          buf_dyn_offset = buf.tell
          dyn.clear
          dyn.read(buf)
          break if dyn.d_tag == ELFTools::Constants::DT_NULL

          yield dyn, buf_dyn_offset
          # there's a possibility for caller to modify @buffer.pos, seek to avoid such issues
          buf.seek buf_dyn_offset + dyn.num_bytes
        end
      end
    end

    # the idea of uniquely identifying section by its name has its problems
    # but this is how patchelf operates and is prone to bugs.
    # e.g: https://github.com/NixOS/patchelf/issues/197
    def find_section(sec_name)
      idx = find_section_idx sec_name
      return unless idx

      @sections[idx]
    end

    def find_section_idx(sec_name)
      @section_idx_by_name[sec_name]
    end

    def buf_grow!(newsz)
      bufsz = @buffer.size
      return if newsz <= bufsz

      @buffer.truncate newsz
    end

    def modify_interpreter
      @replaced_sections['.interp'] = "#{@set[:interpreter]}\x00"
    end

    def modify_needed
      # due to gsoc time constraints only implementing features used by brew.
      raise NotImplementedError
    end

    # not checking for nil as modify_rpath is only called if @set[:rpath]
    def modify_rpath
      modify_rpath_helper @set[:rpath], force_rpath: true
    end

    # not checking for nil as modify_runpath is only called if @set[:runpath]
    def modify_runpath
      modify_rpath_helper @set[:runpath]
    end

    def collect_runpath_tags
      tags = {}
      each_dynamic_tags do |dyn, off|
        case dyn.d_tag
        when ELFTools::Constants::DT_RPATH
          tag_type = :rpath
        when ELFTools::Constants::DT_RUNPATH
          tag_type = :runpath
        else
          next
        end

        # clone does shallow copy, and for some reason d_tag and d_val can't be pass as argument
        dyn_rpath = ELFTools::Structs::ELF_Dyn.new(endian: endian, elf_class: elf_class)
        dyn_rpath.assign({ d_tag: dyn.d_tag.to_i, d_val: dyn.d_val.to_i })
        tags[tag_type] = { offset: off, header: dyn_rpath }
      end
      tags
    end

    def resolve_rpath_tag_conflict(dyn_tags, force_rpath: false)
      dyn_runpath, dyn_rpath = dyn_tags.values_at(:runpath, :rpath)

      update_sym =
        if !force_rpath && dyn_rpath && dyn_runpath.nil?
          :runpath
        elsif force_rpath && dyn_runpath
          :rpath
        end
      return unless update_sym

      delete_sym, = %i[rpath runpath] - [update_sym]
      dyn_tag = dyn_tags[update_sym] = dyn_tags[delete_sym]
      dyn = dyn_tag[:header]
      dyn.d_tag = ELFTools::Constants.const_get("DT_#{update_sym.upcase}")
      with_buf_at(dyn_tag[:offset]) { |buf| dyn.write(buf) }
      dyn_tags.delete(delete_sym)
    end

    def modify_rpath_helper(new_rpath, force_rpath: false)
      shdr_dynstr = dynstr.header

      dyn_tags = collect_runpath_tags
      resolve_rpath_tag_conflict(dyn_tags, force_rpath: force_rpath)
      # (:runpath, :rpath) order_matters.
      resolved_rpath_dyn = dyn_tags.values_at(:runpath, :rpath).compact.first

      old_rpath = ''
      rpath_off = nil
      if resolved_rpath_dyn
        rpath_off = shdr_dynstr.sh_offset + resolved_rpath_dyn[:header].d_val
        old_rpath = buf_cstr(rpath_off)
      end
      return if old_rpath == new_rpath

      with_buf_at(rpath_off) { |b| b.write('X' * old_rpath.size) } if rpath_off
      if new_rpath.size <= old_rpath.size
        with_buf_at(rpath_off) { |b| b.write "#{new_rpath}\x00" }
        return
      end

      Logger.debug 'rpath is too long, resizing...'
      new_dynstr = replace_section '.dynstr', shdr_dynstr.sh_size + new_rpath.size + 1
      new_rpath_strtab_idx = shdr_dynstr.sh_size.to_i
      new_dynstr[new_rpath_strtab_idx..(new_rpath_strtab_idx + new_rpath.size)] = "#{new_rpath}\x00"

      dyn_tags.each_value do |dyn|
        dyn[:header].d_val = new_rpath_strtab_idx
        with_buf_at(dyn[:offset]) { |b| dyn[:header].write(b) }
      end

      return unless dyn_tags.empty?

      add_dt_rpath!(
        d_tag: force_rpath ? ELFTools::Constants::DT_RPATH : ELFTools::Constants::DT_RUNPATH,
        d_val: new_rpath_strtab_idx
      )
    end

    def modify_soname
      return unless ehdr.e_type == ELFTools::Constants::ET_DYN

      # due to gsoc time constraints only implementing features used by brew.
      raise NotImplementedError
    end

    def add_segment!(**phdr_vals)
      new_phdr = ELFTools::Structs::ELF_Phdr[elf_class].new(endian: endian, **phdr_vals)
      # nil = no reference to stream; we only want @segments[i].header
      new_segment = ELFTools::Segments::Segment.new(new_phdr, nil)
      @segments.push new_segment
      ehdr.e_phnum += 1
      nil
    end

    def add_dt_rpath!(d_tag: nil, d_val: nil)
      dyn_num_bytes = nil
      dt_null_idx = 0
      each_dynamic_tags do |dyn|
        dyn_num_bytes ||= dyn.num_bytes
        dt_null_idx += 1
      end

      if dyn_num_bytes.nil?
        Logger.error 'no dynamic tags'
        return
      end

      # allot for new dt_runpath
      shdr_dynamic = find_section('.dynamic').header
      new_dynamic_data = replace_section '.dynamic', shdr_dynamic.sh_size + dyn_num_bytes

      # consider DT_NULL when copying
      replacement_size = (dt_null_idx + 1) * dyn_num_bytes

      # make space for dt_runpath tag at the top, shift data by one tag position
      new_dynamic_data[dyn_num_bytes..(replacement_size + dyn_num_bytes)] = new_dynamic_data[0..replacement_size]

      dyn_rpath = ELFTools::Structs::ELF_Dyn.new endian: endian, elf_class: elf_class
      dyn_rpath.d_tag = d_tag
      dyn_rpath.d_val = d_val

      zi = StringIO.new
      dyn_rpath.write zi
      zi.rewind
      new_dynamic_data[0...dyn_num_bytes] = zi.read
    end

    # given a index into old_sections table
    # returns the corresponding section index in @sections
    #
    # raises ArgumentError if old_shndx can't be found in old_sections
    # TODO: handle case of non existing section in (new) @sections.
    def new_section_idx(old_shndx)
      return if old_shndx == ELFTools::Constants::SHN_UNDEF || old_shndx >= ELFTools::Constants::SHN_LORESERVE

      raise ArgumentError if old_shndx >= old_sections.count

      old_sec = old_sections[old_shndx]
      raise PatchError, "old_sections[#{shndx}] is nil" if old_sec.nil?

      # TODO: handle case of non existing section in (new) @sections.
      find_section_idx(old_sec.name)
    end

    def page_size
      Helper.page_size(ehdr.e_machine)
    end

    def patch_out
      with_buf_at(0) { |b| ehdr.write(b) }

      File.open(out_file, 'wb') do |f|
        @buffer.rewind
        f.write @buffer.read
      end
    end

    # size includes NUL byte
    def replace_section(section_name, size)
      data = @replaced_sections[section_name]
      unless data
        shdr = find_section(section_name).header
        # avoid calling +section.data+ as the @buffer contents may vary from
        # the stream provided to section at initialization.
        # ideally, calling section.data should work, however avoiding it to prevent
        # future traps.
        with_buf_at(shdr.sh_offset) { |b| data = b.read shdr.sh_size }
      end
      rep_data = if data.size == size
                   data
                 elsif data.size < size
                   data.ljust(size, "\x00")
                 else
                   "#{data[0...size]}\x00"
                 end
      @replaced_sections[section_name] = rep_data
    end

    def write_phdrs_to_buf!
      sort_phdrs!
      with_buf_at(ehdr.e_phoff) do |buf|
        @segments.each { |seg| seg.header.write(buf) }
      end
    end

    def write_shdrs_to_buf!
      raise PatchError, 'ehdr.e_shnum != @sections.count' if ehdr.e_shnum != @sections.count

      sort_shdrs!
      with_buf_at(ehdr.e_shoff) do |buf|
        @sections.each { |section| section.header.write(buf) }
      end
      sync_dyn_tags!
    end

    # data for manual packing and unpacking of symbols in symtab sections.
    def meta_sym_pack
      return @meta_sym_pack if @meta_sym_pack

      # resort to manual packing and unpacking of data,
      # as using bindata is painfully slow :(
      if elf_class == 32
        sym_num_bytes = 16 # u32 u32 u32 u8 u8 u16
        pack_code = endian == :little ? 'VVVCCv' : 'NNNCCn'
        pack_st_info = 3
        pack_st_shndx = 5
        pack_st_value = 1
      else # 64
        sym_num_bytes = 24 # u32 u8 u8 u16 u64 u64
        pack_code = endian == :little ? 'VCCvQ<Q<' : 'NCCnQ>Q>'
        pack_st_info = 1
        pack_st_shndx = 3
        pack_st_value = 4
      end

      @meta_sym_pack = {
        num_bytes: sym_num_bytes, code: pack_code,
        st_info: pack_st_info, st_shndx: pack_st_shndx, st_value: pack_st_value
      }
    end

    # yields +symbol+, +entry+
    def each_symbol(shdr)
      return unless [ELFTools::Constants::SHT_SYMTAB, ELFTools::Constants::SHT_DYNSYM].include?(shdr.sh_type)

      pack_code, sym_num_bytes = meta_sym_pack.values_at(:code, :num_bytes)

      with_buf_at(shdr.sh_offset) do |buf|
        num_symbols = shdr.sh_size / sym_num_bytes
        num_symbols.times do |entry|
          sym = buf.read(sym_num_bytes).unpack(pack_code)
          sym_modified = yield sym, entry

          if sym_modified
            buf.seek buf.tell - sym_num_bytes
            buf.write sym.pack(pack_code)
          end
        end
      end
    end

    def rewrite_headers(phdr_address)
      # there can only be a single program header table according to ELF spec
      @segments.find { |seg| seg.header.p_type == ELFTools::Constants::PT_PHDR }&.tap do |seg|
        phdr = seg.header
        phdr.p_offset = ehdr.e_phoff.to_i
        phdr.p_vaddr = phdr.p_paddr = phdr_address.to_i
        phdr.p_filesz = phdr.p_memsz = phdr.num_bytes * @segments.count # e_phentsize * e_phnum
      end
      write_phdrs_to_buf!
      write_shdrs_to_buf!

      pack = meta_sym_pack
      @sections.each do |sec|
        each_symbol(sec.header) do |sym, entry|
          old_shndx = sym[pack[:st_shndx]]

          begin
            new_index = new_section_idx(old_shndx)
          rescue ArgumentError
            Logger.warn "entry #{entry} in symbol table refers to a non existing section, skipping"
          end
          next unless new_index

          sym[pack[:st_shndx]] = new_index

          # right 4 bits in the st_info field is st_type
          if (sym[pack[:st_info]] & 0xF) == ELFTools::Constants::STT_SECTION
            sym[pack[:st_value]] = @sections[new_index].header.sh_addr.to_i
          end
          true
        end
      end
    end

    def rewrite_sections
      return if @replaced_sections.empty?

      case ehdr.e_type
      when ELFTools::Constants::ET_DYN
        rewrite_sections_library
      when ELFTools::Constants::ET_EXEC
        rewrite_sections_executable
      else
        raise PatchError, 'unknown ELF type'
      end
    end

    def replaced_section_indices
      return enum_for(:replaced_section_indices) unless block_given?

      last_replaced = 0
      @sections.each_with_index do |sec, idx|
        if @replaced_sections[sec.name]
          last_replaced = idx
          yield last_replaced
        end
      end
      raise PatchError, 'last_replaced = 0' if last_replaced.zero?
      raise PatchError, 'last_replaced + 1 >= @sections.size' if last_replaced + 1 >= @sections.size
    end

    def start_replacement_shdr
      last_replaced = replaced_section_indices.max
      start_replacement_hdr = @sections[last_replaced + 1].header

      prev_sec_name = ''
      (1..last_replaced).each do |idx|
        sec = @sections[idx]
        shdr = sec.header
        if (sec.type == ELFTools::Constants::SHT_PROGBITS && sec.name != '.interp') || prev_sec_name == '.dynstr'
          start_replacement_hdr = shdr
          break
        elsif @replaced_sections[sec.name].nil?
          Logger.debug " replacing section #{sec.name} which is in the way"
          replace_section(sec.name, shdr.sh_size)
        end
        prev_sec_name = sec.name
      end

      start_replacement_hdr
    end

    def copy_shdrs_to_eof
      shoff_new = @buffer.size
      # honestly idk why `ehdr.e_shoff` is considered when we are only moving shdrs.
      sh_size = ehdr.e_shoff + (ehdr.e_shnum * ehdr.e_shentsize)
      buf_grow! @buffer.size + sh_size
      ehdr.e_shoff = shoff_new
      raise PatchError, 'ehdr.e_shnum != @sections.size' if ehdr.e_shnum != @sections.size

      with_buf_at(ehdr.e_shoff + @sections.first.header.num_bytes) do |buf| # skip writing to NULL section
        @sections.each_with_index do |sec, idx|
          next if idx.zero?

          sec.header.write buf
        end
      end
    end

    def rewrite_sections_executable
      sort_shdrs!
      shdr = start_replacement_shdr
      start_offset = shdr.sh_offset.to_i
      start_addr = shdr.sh_addr.to_i
      first_page = start_addr - start_offset

      Logger.debug "first reserved offset/addr is 0x#{start_offset.to_s 16}/0x#{start_addr.to_s 16}"

      unless start_addr % page_size == start_offset % page_size
        raise PatchError, 'start_addr != start_offset (mod PAGE_SIZE)'
      end

      Logger.debug "first page is 0x#{first_page.to_i.to_s 16}"

      copy_shdrs_to_eof if ehdr.e_shoff < start_offset

      normalize_note_segments

      seg_num_bytes = @segments.first.header.num_bytes
      needed_space = (
        ehdr.num_bytes +
        (@segments.count * seg_num_bytes) +
        @replaced_sections.sum { |_, str| Helper.alignup(str.size, @section_alignment) }
      )

      if needed_space > start_offset
        needed_space += seg_num_bytes # new load segment is required

        extra_bytes = needed_space - start_offset
        needed_pages = Helper.alignup(extra_bytes, page_size) / page_size
        Logger.debug "needed pages is #{needed_pages}"
        raise PatchError, 'virtual address space underrun' if needed_pages * page_size > first_page

        shift_file(needed_pages, start_offset, extra_bytes)

        first_page -= needed_pages * page_size
        start_offset += needed_pages * page_size
      end
      Logger.debug "needed space is #{needed_space}"

      cur_off = ehdr.num_bytes + (@segments.count * seg_num_bytes)
      Logger.debug "clearing first #{start_offset - cur_off} bytes"
      with_buf_at(cur_off) { |buf| buf.fill("\x00", (start_offset - cur_off)) }

      cur_off = write_replaced_sections cur_off, first_page, 0
      raise PatchError, "cur_off(#{cur_off}) != needed_space" if cur_off != needed_space

      rewrite_headers first_page + ehdr.e_phoff
    end

    def replace_sections_in_the_way_of_phdr!
      num_notes = @sections.count { |sec| sec.type == ELFTools::Constants::SHT_NOTE }
      pht_size = ehdr.num_bytes + ((@segments.count + num_notes + 1) * @segments.first.header.num_bytes)

      # replace sections that may overlap with expanded program header table
      @sections.each_with_index do |sec, idx|
        shdr = sec.header
        next if idx.zero? || @replaced_sections[sec.name]
        break if shdr.sh_offset > pht_size

        replace_section sec.name, shdr.sh_size
      end
    end

    def rewrite_sections_library
      start_page = 0
      first_page = 0
      @segments.each do |seg|
        phdr = seg.header
        this_page = Helper.alignup(phdr.p_vaddr + phdr.p_memsz, page_size)
        start_page = [start_page, this_page].max
        first_page = phdr.p_vaddr - phdr.p_offset if phdr.p_type == ELFTools::Constants::PT_PHDR
      end

      Logger.debug "Last page is 0x#{start_page.to_s 16}"
      Logger.debug "First page is 0x#{first_page.to_s 16}"
      replace_sections_in_the_way_of_phdr!
      needed_space = @replaced_sections.sum { |_, str| Helper.alignup(str.size, @section_alignment) }
      Logger.debug "needed space = #{needed_space}"

      start_offset = Helper.alignup(@buffer.size, page_size)
      buf_grow! start_offset + needed_space

      # executable shared object
      if start_offset > start_page && @segments.any? { |seg| seg.header.p_type == ELFTools::Constants::PT_INTERP }
        Logger.debug(
          "shifting new PT_LOAD segment by #{start_offset - start_page} bytes to work around a Linux kernel bug"
        )
        start_page = start_offset
      end

      ehdr.e_phoff = ehdr.num_bytes
      add_segment!(
        p_type: ELFTools::Constants::PT_LOAD,
        p_offset: start_offset,
        p_vaddr: start_page,
        p_paddr: start_page,
        p_filesz: needed_space,
        p_memsz: needed_space,
        p_flags: ELFTools::Constants::PF_R | ELFTools::Constants::PF_W,
        p_align: page_size
      )

      normalize_note_segments

      cur_off = write_replaced_sections start_offset, start_page, start_offset
      raise PatchError, 'cur_off != start_offset + needed_space' if cur_off != start_offset + needed_space

      rewrite_headers(first_page + ehdr.e_phoff)
    end

    def normalize_note_segments
      return if @replaced_sections.none? do |rsec_name, _|
        find_section(rsec_name)&.type == ELFTools::Constants::SHT_NOTE
      end

      new_phdrs = []

      phdrs_by_type(ELFTools::Constants::PT_NOTE) do |phdr|
        # Binaries produced by older patchelf versions may contain empty PT_NOTE segments.
        next if @sections.none? do |sec|
          sec.header.sh_offset >= phdr.p_offset && sec.header.sh_offset < phdr.p_offset + phdr.p_filesz
        end

        new_phdrs += normalize_note_segment(phdr)
      end

      new_phdrs.each { |phdr| add_segment!(**phdr.snapshot) }
    end

    def normalize_note_segment(phdr)
      start_off = phdr.p_offset.to_i
      curr_off = start_off
      end_off = start_off + phdr.p_filesz

      new_phdrs = []

      while curr_off < end_off
        size = 0
        sections_at_aligned_offset(curr_off) do |sec|
          next if sec.type != ELFTools::Constants::SHT_NOTE

          size = sec.header.sh_size.to_i
          curr_off = sec.header.sh_offset.to_i
          break
        end

        raise PatchError, 'cannot normalize PT_NOTE segment: non-contiguous SHT_NOTE sections' if size.zero?

        if curr_off + size > end_off
          raise PatchError, 'cannot normalize PT_NOTE segment: partially mapped SHT_NOTE section'
        end

        new_phdr = ELFTools::Structs::ELF_Phdr[elf_class].new(endian: endian, **phdr.snapshot)
        new_phdr.p_offset = curr_off
        new_phdr.p_vaddr = phdr.p_vaddr + (curr_off - start_off)
        new_phdr.p_paddr = phdr.p_paddr + (curr_off - start_off)
        new_phdr.p_filesz = size
        new_phdr.p_memsz = size

        if curr_off == start_off
          phdr.assign(new_phdr)
        else
          new_phdrs << new_phdr
        end

        curr_off += size
      end

      new_phdrs
    end

    def sections_at_aligned_offset(offset)
      @sections.each do |sec|
        shdr = sec.header

        aligned_offset = Helper.alignup(offset, shdr.sh_addralign)
        next if shdr.sh_offset != aligned_offset

        yield sec
      end
    end

    def shift_sections(shift, start_offset)
      ehdr.e_shoff += shift if ehdr.e_shoff >= start_offset

      @sections.each_with_index do |sec, i|
        next if i.zero? # dont touch NULL section

        shdr = sec.header
        next if shdr.sh_offset < start_offset

        shdr.sh_offset += shift
      end
    end

    def shift_segment_offset(phdr, shift)
      phdr.p_offset += shift
      phdr.p_align = page_size if phdr.p_align != 0 && (phdr.p_vaddr - phdr.p_offset) % phdr.p_align != 0
    end

    def shift_segment_virtual_address(phdr, shift)
      phdr.p_paddr -= shift if phdr.p_paddr > shift
      phdr.p_vaddr -= shift if phdr.p_vaddr > shift
    end

    # rubocop:disable Metrics/PerceivedComplexity
    def shift_segments(shift, start_offset)
      split_index = -1
      split_shift = 0

      @segments.each_with_index do |seg, idx|
        phdr = seg.header
        p_start = phdr.p_offset

        if p_start <= start_offset && p_start + phdr.p_filesz > start_offset &&
           phdr.p_type == ELFTools::Constants::PT_LOAD
          raise PatchError, "split_index(#{split_index}) != -1" if split_index != -1

          split_index = idx
          split_shift = start_offset - p_start

          phdr.p_offset = start_offset
          phdr.p_memsz -= split_shift
          phdr.p_filesz -= split_shift
          phdr.p_paddr += split_shift
          phdr.p_vaddr += split_shift

          p_start = start_offset
        end

        if p_start >= start_offset
          shift_segment_offset(phdr, shift)
        else
          shift_segment_virtual_address(phdr, shift)
        end
      end

      raise PatchError, "split_index(#{split_index}) == -1" if split_index == -1

      [split_index, split_shift]
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def shift_file(extra_pages, start_offset, extra_bytes)
      raise PatchError, "start_offset(#{start_offset}) < ehdr.num_bytes" if start_offset < ehdr.num_bytes

      oldsz = @buffer.size
      raise PatchError, "oldsz <= start_offset(#{start_offset})" if oldsz <= start_offset

      shift = extra_pages * page_size
      buf_grow!(oldsz + shift)
      buf_move!(start_offset + shift, start_offset, oldsz - start_offset)
      with_buf_at(start_offset) { |buf| buf.write "\x00" * shift }

      ehdr.e_phoff = ehdr.num_bytes

      shift_sections(shift, start_offset)

      split_index, split_shift = shift_segments(shift, start_offset)

      split_phdr = @segments[split_index].header
      add_segment!(
        p_type: ELFTools::Constants::PT_LOAD,
        p_offset: split_phdr.p_offset - split_shift - shift,
        p_vaddr: split_phdr.p_vaddr - split_shift - shift,
        p_paddr: split_phdr.p_paddr - split_shift - shift,
        p_filesz: split_shift + extra_bytes,
        p_memsz: split_shift + extra_bytes,
        p_flags: ELFTools::Constants::PF_R | ELFTools::Constants::PF_W,
        p_align: page_size
      )
    end

    def sort_phdrs!
      pt_phdr = ELFTools::Constants::PT_PHDR
      @segments.sort! do |me, you|
        next  1 if you.header.p_type == pt_phdr
        next -1 if me.header.p_type == pt_phdr

        me.header.p_paddr.to_i <=> you.header.p_paddr.to_i
      end
    end

    # section headers may contain sh_info and sh_link values that are
    # references to another section
    def collect_section_to_section_refs
      rel_syms = [ELFTools::Constants::SHT_REL, ELFTools::Constants::SHT_RELA]
      # Translate sh_link, sh_info mappings to section names.
      @sections.each_with_object({ linkage: {}, info: {} }) do |s, collected|
        hdr = s.header
        collected[:linkage][s.name] = @sections[hdr.sh_link].name if hdr.sh_link.nonzero?
        collected[:info][s.name] = @sections[hdr.sh_info].name if hdr.sh_info.nonzero? && rel_syms.include?(hdr.sh_type)
      end
    end

    # @param collected
    # this must be the value returned by +collect_section_to_section_refs+
    def restore_section_to_section_refs!(collected)
      rel_syms = [ELFTools::Constants::SHT_REL, ELFTools::Constants::SHT_RELA]
      linkage, info = collected.values_at(:linkage, :info)
      @sections.each do |sec|
        hdr = sec.header
        hdr.sh_link = find_section_idx(linkage[sec.name]) if hdr.sh_link.nonzero?
        hdr.sh_info = find_section_idx(info[sec.name]) if hdr.sh_info.nonzero? && rel_syms.include?(hdr.sh_type)
      end
    end

    def sort_shdrs!
      return if @sections.empty?

      section_dep_values = collect_section_to_section_refs
      shstrtab = @sections[ehdr.e_shstrndx].header
      @sections.sort! { |me, you| me.header.sh_offset.to_i <=> you.header.sh_offset.to_i }
      update_section_idx!
      restore_section_to_section_refs!(section_dep_values)
      @sections.each_with_index do |sec, idx|
        ehdr.e_shstrndx = idx if sec.header.sh_offset == shstrtab.sh_offset
      end
    end

    def jmprel_section_name
      sec_name = %w[.rel.plt .rela.plt .rela.IA_64.pltoff].find { |s| find_section(s) }
      raise PatchError, 'cannot find section corresponding to DT_JMPREL' unless sec_name

      sec_name
    end

    # given a +dyn.d_tag+, returns the section name it must be synced to.
    # it may return nil, when given tag maps to no section,
    # or when its okay to skip if section is not found.
    def dyn_tag_to_section_name(d_tag)
      case d_tag
      when ELFTools::Constants::DT_STRTAB, ELFTools::Constants::DT_STRSZ
        '.dynstr'
      when ELFTools::Constants::DT_SYMTAB
        '.dynsym'
      when ELFTools::Constants::DT_HASH
        '.hash'
      when ELFTools::Constants::DT_GNU_HASH
        # return nil if not found, patchelf claims no problem in skipping
        find_section('.gnu.hash')&.name
      when ELFTools::Constants::DT_MIPS_XHASH
        return if ehdr.e_machine != ELFTools::Constants::EM_MIPS

        '.MIPS.xhash'
      when ELFTools::Constants::DT_JMPREL
        jmprel_section_name
      when ELFTools::Constants::DT_REL
        # regarding .rel.got, NixOS/patchelf says
        # "no idea if this makes sense, but it was needed for some program"
        #
        # return nil if not found, patchelf claims no problem in skipping
        %w[.rel.dyn .rel.got].find { |s| find_section(s) }
      when ELFTools::Constants::DT_RELA
        # return nil if not found, patchelf claims no problem in skipping
        find_section('.rela.dyn')&.name
      when ELFTools::Constants::DT_VERNEED
        '.gnu.version_r'
      when ELFTools::Constants::DT_VERSYM
        '.gnu.version'
      end
    end

    # updates dyn tags by syncing it with @section values
    def sync_dyn_tags!
      dyn_table_offset = nil
      each_dynamic_tags do |dyn, buf_off|
        dyn_table_offset ||= buf_off

        sec_name = dyn_tag_to_section_name(dyn.d_tag)

        unless sec_name
          if dyn.d_tag == ELFTools::Constants::DT_MIPS_RLD_MAP_REL && ehdr.e_machine == ELFTools::Constants::EM_MIPS
            rld_map = find_section('.rld_map')
            dyn.d_val = if rld_map
                          rld_map.header.sh_addr.to_i - (buf_off - dyn_table_offset) -
                            find_section('.dynamic').header.sh_addr.to_i
                        else
                          Logger.warn 'DT_MIPS_RLD_MAP_REL entry is present, but .rld_map section is not'
                          0
                        end
          end

          next
        end

        shdr = find_section(sec_name).header
        dyn.d_val = dyn.d_tag == ELFTools::Constants::DT_STRSZ ? shdr.sh_size.to_i : shdr.sh_addr.to_i

        with_buf_at(buf_off) { |wbuf| dyn.write(wbuf) }
      end
    end

    def update_section_idx!
      @section_idx_by_name = @sections.map.with_index { |sec, idx| [sec.name, idx] }.to_h
    end

    def with_buf_at(pos)
      return unless block_given?

      opos = @buffer.tell
      @buffer.seek pos
      yield @buffer
      @buffer.seek opos
      nil
    end

    def sync_sec_to_seg(shdr, phdr)
      phdr.p_offset = shdr.sh_offset.to_i
      phdr.p_vaddr = phdr.p_paddr = shdr.sh_addr.to_i
      phdr.p_filesz = phdr.p_memsz = shdr.sh_size.to_i
    end

    def phdrs_by_type(seg_type)
      return unless seg_type

      @segments.each_with_index do |seg, idx|
        next unless (phdr = seg.header).p_type == seg_type

        yield phdr, idx
      end
    end

    # Returns a blank shdr if the section doesn't exist.
    def find_or_create_section_header(rsec_name)
      shdr = find_section(rsec_name)&.header
      shdr ||= ELFTools::Structs::ELF_Shdr.new(endian: endian, elf_class: elf_class)
      shdr
    end

    def overwrite_replaced_sections
      # the original source says this has to be done separately to
      # prevent clobbering the previously written section contents.
      @replaced_sections.each_key do |rsec_name|
        shdr = find_section(rsec_name)&.header
        next unless shdr

        next if shdr.sh_type == ELFTools::Constants::SHT_NOBITS

        with_buf_at(shdr.sh_offset) { |b| b.fill('X', shdr.sh_size) }
      end
    end

    def write_section_alignment(shdr)
      return if shdr.sh_type == ELFTools::Constants::SHT_NOTE && shdr.sh_addralign <= @section_alignment

      shdr.sh_addralign = @section_alignment
    end

    def section_bounds_within_segment?(s_start, s_end, p_start, p_end)
      (s_start >= p_start && s_start < p_end) || (s_end > p_start && s_end <= p_end)
    end

    def write_replaced_sections(cur_off, start_addr, start_offset)
      overwrite_replaced_sections

      noted_phdrs = Set.new

      # the sort is necessary, the strategy in ruby and Cpp to iterate map/hash
      # is different, patchelf v0.10 iterates the replaced_sections sorted by
      # keys.
      @replaced_sections.sort.each do |rsec_name, rsec_data|
        shdr = find_or_create_section_header(rsec_name)

        Logger.debug <<~DEBUG
          rewriting section '#{rsec_name}'
          from offset 0x#{shdr.sh_offset.to_i.to_s 16}(size #{shdr.sh_size})
            to offset 0x#{cur_off.to_i.to_s 16}(size #{rsec_data.size})
        DEBUG

        with_buf_at(cur_off) { |b| b.write rsec_data }

        orig_sh_offset = shdr.sh_offset.to_i
        orig_sh_size = shdr.sh_size.to_i

        shdr.sh_offset = cur_off
        shdr.sh_addr = start_addr + (cur_off - start_offset)
        shdr.sh_size = rsec_data.size

        write_section_alignment(shdr)

        seg_type = {
          '.interp' => ELFTools::Constants::PT_INTERP,
          '.dynamic' => ELFTools::Constants::PT_DYNAMIC,
          '.MIPS.abiflags' => ELFTools::Constants::PT_MIPS_ABIFLAGS,
          '.note.gnu.property' => ELFTools::Constants::PT_GNU_PROPERTY
        }[rsec_name]

        phdrs_by_type(seg_type) { |phdr| sync_sec_to_seg(shdr, phdr) }

        if shdr.sh_type == ELFTools::Constants::SHT_NOTE
          phdrs_by_type(ELFTools::Constants::PT_NOTE) do |phdr, idx|
            next if noted_phdrs.include?(idx)

            s_start = orig_sh_offset
            s_end = s_start + orig_sh_size
            p_start = phdr.p_offset
            p_end = p_start + phdr.p_filesz

            next unless section_bounds_within_segment?(s_start, s_end, p_start, p_end)

            raise PatchError, 'unsupported overlap of SHT_NOTE and PT_NOTE' if p_start != s_start || p_end != s_end

            sync_sec_to_seg(shdr, phdr)

            noted_phdrs << idx
          end
        end

        cur_off += Helper.alignup(rsec_data.size, @section_alignment)
      end
      @replaced_sections.clear

      cur_off
    end
  end
end
