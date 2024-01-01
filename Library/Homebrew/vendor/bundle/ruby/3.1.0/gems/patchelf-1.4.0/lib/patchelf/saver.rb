# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/elf_file'
require 'elftools/structs'
require 'elftools/util'
require 'fileutils'

require 'patchelf/mm'

module PatchELF
  # Internal use only.
  #
  # For {Patcher} to do patching things and save to file.
  # @private
  class Saver
    attr_reader :in_file # @return [String] Input filename.
    attr_reader :out_file # @return [String] Output filename.

    # Instantiate a {Saver} object.
    # @param [String] in_file
    # @param [String] out_file
    # @param [{Symbol => String, Array}] set
    def initialize(in_file, out_file, set)
      @in_file = in_file
      @out_file = out_file
      @set = set
      # [{Integer => String}]
      @inline_patch = {}
      @elf = ELFTools::ELFFile.new(File.open(in_file))
      @mm = PatchELF::MM.new(@elf)
      @strtab_extend_requests = []
      @append_dyn = []
    end

    # @return [void]
    def save!
      # In this method we assume all attributes that should exist do exist.
      # e.g. DT_INTERP, DT_DYNAMIC. These should have been checked in the patcher.
      patch_interpreter
      patch_dynamic

      @mm.dispatch!

      FileUtils.cp(in_file, out_file) if out_file != in_file
      patch_out(@out_file)
      # Let output file have the same permission as input.
      FileUtils.chmod(File.stat(in_file).mode, out_file)
    end

    private

    def patch_interpreter
      return if @set[:interpreter].nil?

      new_interp = "#{@set[:interpreter]}\x00"
      old_interp = "#{@elf.segment_by_type(:interp).interp_name}\x00"
      return if old_interp == new_interp

      # These headers must be found here but not in the proc.
      seg_header = @elf.segment_by_type(:interp).header
      sec_header = section_header('.interp')

      patch = proc do |off, vaddr|
        # Register an inline patching
        inline_patch(off, new_interp)

        # The patching feature of ELFTools
        seg_header.p_offset = off
        seg_header.p_vaddr = seg_header.p_paddr = vaddr
        seg_header.p_filesz = seg_header.p_memsz = new_interp.size

        if sec_header
          sec_header.sh_offset = off
          sec_header.sh_size = new_interp.size
        end
      end

      if new_interp.size <= old_interp.size
        # easy case
        patch.call(seg_header.p_offset.to_i, seg_header.p_vaddr.to_i)
      else
        # hard case, we have to request a new LOAD area
        @mm.malloc(new_interp.size, &patch)
      end
    end

    def patch_dynamic
      # We never do inline patching on strtab's string.
      # 1. Search if there's useful string exists
      #   - only need header patching
      # 2. Append a new string to the strtab.
      #   - register strtab extension
      dynamic.tags # HACK, force @tags to be defined
      patch_soname if @set[:soname]
      patch_runpath if @set[:runpath]
      patch_runpath(:rpath) if @set[:rpath]
      patch_needed if @set[:needed]
      malloc_strtab!
      expand_dynamic!
    end

    def patch_soname
      # The tag must exist.
      so_tag = dynamic.tag_by_type(:soname)
      reg_str_table(@set[:soname]) do |idx|
        so_tag.header.d_val = idx
      end
    end

    def patch_runpath(sym = :runpath)
      tag = dynamic.tag_by_type(sym)
      tag = tag.nil? ? lazy_dyn(sym) : tag.header
      reg_str_table(@set[sym]) do |idx|
        tag.d_val = idx
      end
    end

    # To mark a not-using tag
    IGNORE = ELFTools::Constants::DT_LOOS
    def patch_needed
      original_needs = dynamic.tags_by_type(:needed)
      @set[:needed].uniq!

      original = original_needs.map(&:name)
      replace = @set[:needed]

      # 3 sets:
      # 1. in original and in needs - remain unchanged
      # 2. in original but not in needs - remove
      # 3. not in original and in needs - append
      append = replace - original
      remove = original - replace

      ignored_dyns = remove.each_with_object([]) do |name, ignored|
        dyn = original_needs.find { |n| n.name == name }.header
        dyn.d_tag = IGNORE
        ignored << dyn
      end

      append.zip(ignored_dyns) do |name, ignored_dyn|
        dyn = ignored_dyn || lazy_dyn(:needed)
        dyn.d_tag = ELFTools::Constants::DT_NEEDED
        reg_str_table(name) { |idx| dyn.d_val = idx }
      end
    end

    # Create a temp tag header.
    # @return [ELFTools::Structs::ELF_Dyn]
    def lazy_dyn(sym)
      ELFTools::Structs::ELF_Dyn.new(endian: @elf.endian).tap do |dyn|
        @append_dyn << dyn
        dyn.elf_class = @elf.elf_class
        dyn.d_tag = ELFTools::Util.to_constant(ELFTools::Constants::DT, sym)
      end
    end

    def expand_dynamic!
      return if @append_dyn.empty?

      dyn_sec = section_header('.dynamic')
      total = dynamic.tags.map(&:header)
      # the last must be a null-tag
      total = total[0..-2] + @append_dyn + [total.last]
      bytes = total.first.num_bytes * total.size
      @mm.malloc(bytes) do |off, vaddr|
        inline_patch(off, total.map(&:to_binary_s).join)
        dynamic.header.p_offset = off
        dynamic.header.p_vaddr = dynamic.header.p_paddr = vaddr
        dynamic.header.p_filesz = dynamic.header.p_memsz = bytes
        if dyn_sec
          dyn_sec.sh_offset = off
          dyn_sec.sh_addr = vaddr
          dyn_sec.sh_size = bytes
        end
      end
    end

    def malloc_strtab!
      return if @strtab_extend_requests.empty?

      strtab = dynamic.tag_by_type(:strtab)
      # Process registered requests
      need_size = strtab_string.size + @strtab_extend_requests.reduce(0) { |sum, (str, _)| sum + str.size + 1 }
      dynstr = section_header('.dynstr')
      @mm.malloc(need_size) do |off, vaddr|
        new_str = "#{strtab_string}#{@strtab_extend_requests.map(&:first).join("\x00")}\x00"
        inline_patch(off, new_str)
        cur = strtab_string.size
        @strtab_extend_requests.each do |str, block|
          block.call(cur)
          cur += str.size + 1
        end
        # Now patching strtab header
        strtab.header.d_val = vaddr
        # We also need to patch dynstr to let readelf have correct output.
        if dynstr
          dynstr.sh_size = new_str.size
          dynstr.sh_offset = off
          dynstr.sh_addr = vaddr
        end
      end
    end

    # @param [String] str
    # @yieldparam [Integer] idx
    # @yieldreturn [void]
    def reg_str_table(str, &block)
      idx = strtab_string.index("#{str}\x00")
      # Request string is already exist
      return yield idx if idx

      # Record the request
      @strtab_extend_requests << [str, block]
    end

    def strtab_string
      return @strtab_string if defined?(@strtab_string)

      # TODO: handle no strtab exists..
      offset = @elf.offset_from_vma(dynamic.tag_by_type(:strtab).value)
      # This is a little tricky since no length information is stored in the tag.
      # We first get the file offset of the string then 'guess' where the end is.
      @elf.stream.pos = offset
      @strtab_string = +''
      loop do
        c = @elf.stream.read(1)
        break unless c =~ /\x00|[[:print:]]/

        @strtab_string << c
      end
      @strtab_string
    end

    # This can only be used for patching interpreter's name
    # or set strings in a malloc-ed area.
    # i.e. NEVER intend to change the string defined in strtab
    def inline_patch(off, str)
      @inline_patch[off] = str
    end

    # Modify the out_file according to registered patches.
    def patch_out(out_file)
      File.open(out_file, 'r+') do |f|
        if @mm.extended?
          original_head = @mm.threshold
          extra = {}
          # Copy all data after the second load
          @elf.stream.pos = original_head
          extra[original_head + @mm.extend_size] = @elf.stream.read # read to end
          # zero out the 'gap' we created
          extra[original_head] = "\x00" * @mm.extend_size
          extra.each do |pos, str|
            f.pos = pos
            f.write(str)
          end
        end
        @elf.patches.each do |pos, str|
          f.pos = @mm.extended_offset(pos)
          f.write(str)
        end

        @inline_patch.each do |pos, str|
          f.pos = pos
          f.write(str)
        end
      end
    end

    # @return [ELFTools::Sections::Section?]
    def section_header(name)
      sec = @elf.section_by_name(name)
      return if sec.nil?

      sec.header
    end

    def dynamic
      @dynamic ||= @elf.segment_by_type(:dynamic)
    end
  end
end
