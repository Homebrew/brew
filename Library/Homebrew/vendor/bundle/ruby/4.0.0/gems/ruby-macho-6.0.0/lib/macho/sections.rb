# frozen_string_literal: true

module MachO
  # Classes and constants for parsing sections in Mach-O binaries.
  module Sections
    # type mask
    SECTION_TYPE_MASK = 0x000000ff

    # attributes mask
    SECTION_ATTRIBUTES_MASK = 0xffffff00

    # user settable attributes mask
    SECTION_ATTRIBUTES_USR_MASK = 0xff000000

    # system settable attributes mask
    SECTION_ATTRIBUTES_SYS_MASK = 0x00ffff00

    # maximum specifiable section alignment, as a power of 2
    # @note see `MAXSECTALIGN` macro in `cctools/misc/lipo.c`
    MAX_SECT_ALIGN = 15

    # association of section type symbols to values
    # @api private
    SECTION_TYPES = {
      :S_REGULAR => 0x0,
      :S_ZEROFILL => 0x1,
      :S_CSTRING_LITERALS => 0x2,
      :S_4BYTE_LITERALS => 0x3,
      :S_8BYTE_LITERALS => 0x4,
      :S_LITERAL_POINTERS => 0x5,
      :S_NON_LAZY_SYMBOL_POINTERS => 0x6,
      :S_LAZY_SYMBOL_POINTERS => 0x7,
      :S_SYMBOL_STUBS => 0x8,
      :S_MOD_INIT_FUNC_POINTERS => 0x9,
      :S_MOD_TERM_FUNC_POINTERS => 0xa,
      :S_COALESCED => 0xb,
      :S_GB_ZEROFILE => 0xc,
      :S_INTERPOSING => 0xd,
      :S_16BYTE_LITERALS => 0xe,
      :S_DTRACE_DOF => 0xf,
      :S_LAZY_DYLIB_SYMBOL_POINTERS => 0x10,
      :S_THREAD_LOCAL_REGULAR => 0x11,
      :S_THREAD_LOCAL_ZEROFILL => 0x12,
      :S_THREAD_LOCAL_VARIABLES => 0x13,
      :S_THREAD_LOCAL_VARIABLE_POINTERS => 0x14,
      :S_THREAD_LOCAL_INIT_FUNCTION_POINTERS => 0x15,
      :S_INIT_FUNC_OFFSETS => 0x16,
    }.freeze

    # association of section attribute symbols to values
    # @api private
    SECTION_ATTRIBUTES = {
      :S_ATTR_PURE_INSTRUCTIONS => 0x80000000,
      :S_ATTR_NO_TOC => 0x40000000,
      :S_ATTR_STRIP_STATIC_SYMS => 0x20000000,
      :S_ATTR_NO_DEAD_STRIP => 0x10000000,
      :S_ATTR_LIVE_SUPPORT => 0x08000000,
      :S_ATTR_SELF_MODIFYING_CODE => 0x04000000,
      :S_ATTR_DEBUG => 0x02000000,
      :S_ATTR_SOME_INSTRUCTIONS => 0x00000400,
      :S_ATTR_EXT_RELOC => 0x00000200,
      :S_ATTR_LOC_RELOC => 0x00000100,
    }.freeze

    # association of section flag symbols to values
    # @api private
    SECTION_FLAGS = {
      **SECTION_TYPES,
      **SECTION_ATTRIBUTES,
    }.freeze

    # association of section name symbols to names
    # @api private
    SECTION_NAMES = {
      :SECT_TEXT => "__text",
      :SECT_FVMLIB_INIT0 => "__fvmlib_init0",
      :SECT_FVMLIB_INIT1 => "__fvmlib_init1",
      :SECT_DATA => "__data",
      :SECT_BSS => "__bss",
      :SECT_COMMON => "__common",
      :SECT_OBJC_SYMBOLS => "__symbol_table",
      :SECT_OBJC_MODULES => "__module_info",
      :SECT_OBJC_STRINGS => "__selector_strs",
      :SECT_OBJC_REFS => "__selector_refs",
      :SECT_ICON_HEADER => "__header",
      :SECT_ICON_TIFF => "__tiff",
    }.freeze

    # Represents a section of a segment for 32-bit architectures.
    class Section < MachOStructure
      # @return [String] the name of the section, including null pad bytes
      field :sectname, :string, :padding => :null, :size => 16

      # @return [String] the name of the segment's section, including null
      #  pad bytes
      field :segname, :string, :padding => :null, :size => 16

      # @return [Integer] the memory address of the section
      field :addr, :uint32

      # @return [Integer] the size, in bytes, of the section
      field :size, :uint32

      # @return [Integer] the file offset of the section
      field :offset, :uint32

      # @return [Integer] the section alignment (power of 2) of the section
      field :align, :uint32

      # @return [Integer] the file offset of the section's relocation entries
      field :reloff, :uint32

      # @return [Integer] the number of relocation entries
      field :nreloc, :uint32

      # @return [Integer] flags for type and attributes of the section
      field :flags, :uint32

      # @return [void] reserved (for offset or index)
      field :reserved1, :uint32

      # @return [void] reserved (for count or sizeof)
      field :reserved2, :uint32

      # @return [String] the section's name
      def section_name
        sectname
      end

      # @return [String] the parent segment's name
      def segment_name
        segname
      end

      # @return [Boolean] whether the section is empty (i.e, {size} is 0)
      def empty?
        size.zero?
      end

      # @return [Integer] the raw numeric type of this section
      def type
        flags & SECTION_TYPE_MASK
      end

      # @example
      #  puts "this section is regular" if sect.type?(:S_REGULAR)
      # @param type_sym [Symbol] a section type symbol
      # @return [Boolean] whether this section is of the given type
      def type?(type_sym)
        type == SECTION_TYPES[type_sym]
      end

      # @return [Integer] the raw numeric attributes of this section
      def attributes
        flags & SECTION_ATTRIBUTES_MASK
      end

      # @example
      #  puts "pure instructions" if sect.attribute?(:S_ATTR_PURE_INSTRUCTIONS)
      # @param attr_sym [Symbol] a section attribute symbol
      # @return [Boolean] whether this section is of the given type
      def attribute?(attr_sym)
        !!(attributes & SECTION_ATTRIBUTES[attr_sym])
      end

      # @deprecated Use {#type?} or {#attribute?} instead.
      # @example
      #  puts "this section is regular" if sect.flag?(:S_REGULAR)
      # @param flag [Symbol] a section flag symbol
      # @return [Boolean] whether the flag is present in the section's {flags}
      def flag?(flag)
        flag = SECTION_FLAGS[flag]

        return false if flag.nil?

        flags & flag == flag
      end

      # @return [Hash] a hash representation of this {Section}
      def to_h
        {
          "sectname" => sectname,
          "segname" => segname,
          "addr" => addr,
          "size" => size,
          "offset" => offset,
          "align" => align,
          "reloff" => reloff,
          "nreloc" => nreloc,
          "flags" => flags,
          "reserved1" => reserved1,
          "reserved2" => reserved2,
        }.merge super
      end
    end

    # Represents a section of a segment for 64-bit architectures.
    class Section64 < Section
      # @return [Integer] the memory address of the section
      field :addr, :uint64

      # @return [Integer] the size, in bytes, of the section
      field :size, :uint64

      # @return [void] reserved
      field :reserved3, :uint32

      # @return [Hash] a hash representation of this {Section64}
      def to_h
        {
          "reserved3" => reserved3,
        }.merge super
      end
    end
  end
end
