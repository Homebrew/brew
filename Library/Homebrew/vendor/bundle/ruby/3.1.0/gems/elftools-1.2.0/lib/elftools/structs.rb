# frozen_string_literal: true

require 'bindata'

module ELFTools
  # Define ELF related structures in this module.
  #
  # Structures are fetched from https://github.com/torvalds/linux/blob/master/include/uapi/linux/elf.h.
  # Use gem +bindata+ to have these structures support 32/64 bits and little/big endian simultaneously.
  module Structs
    # The base structure to define common methods.
    class ELFStruct < BinData::Record
      # DRY. Many fields have different type in different arch.
      CHOICE_SIZE_T = proc do |t = 'uint'|
        { selection: :elf_class, choices: { 32 => :"#{t}32", 64 => :"#{t}64" }, copy_on_change: true }
      end

      attr_accessor :elf_class # @return [Integer] 32 or 64.
      attr_accessor :offset # @return [Integer] The file offset of this header.

      # Records which fields have been patched.
      # @return [Hash{Integer => Integer}] Patches.
      def patches
        @patches ||= {}
      end

      # BinData hash(Snapshot) that behaves like HashWithIndifferentAccess
      alias to_h snapshot

      class << self
        # Hooks the constructor.
        #
        # +BinData::Record+ doesn't allow us to override +#initialize+, so we hack +new+ here.
        def new(*args)
          # XXX: The better implementation is +new(*args, **kwargs)+, but we can't do this unless bindata changed
          # lib/bindata/dsl.rb#override_new_in_class to invoke +new+ with both +args+ and +kwargs+.
          kwargs = args.last.is_a?(Hash) ? args.last : {}
          offset = kwargs.delete(:offset)
          super.tap do |obj|
            obj.offset = offset
            obj.field_names.each do |f|
              m = "#{f}=".to_sym
              old_method = obj.singleton_method(m)
              obj.singleton_class.send(:undef_method, m)
              obj.define_singleton_method(m) do |val|
                org = obj.send(f)
                obj.patches[org.abs_offset] = ELFStruct.pack(val, org.num_bytes)
                old_method.call(val)
              end
            end
          end
        end

        # Gets the endianness of current class.
        # @return [:little, :big] The endianness.
        def self_endian
          bindata_name[-2..] == 'be' ? :big : :little
        end

        # Packs an integer to string.
        # @param [Integer] val
        # @param [Integer] bytes
        # @return [String]
        def pack(val, bytes)
          raise ArgumentError, "Not supported assign type #{val.class}" unless val.is_a?(Integer)

          number = val & ((1 << (8 * bytes)) - 1)
          out = []
          bytes.times do
            out << (number & 0xff)
            number >>= 8
          end
          out = out.pack('C*')
          self_endian == :little ? out : out.reverse
        end
      end
    end

    # ELF header structure.
    class ELF_Ehdr < ELFStruct
      endian :big_and_little
      struct :e_ident do
        string :magic, read_length: 4
        int8 :ei_class
        int8 :ei_data
        int8 :ei_version
        int8 :ei_osabi
        int8 :ei_abiversion
        string :ei_padding, read_length: 7 # no use
      end
      uint16 :e_type
      uint16 :e_machine
      uint32 :e_version
      # entry point
      choice :e_entry, **CHOICE_SIZE_T['uint']
      choice :e_phoff, **CHOICE_SIZE_T['uint']
      choice :e_shoff, **CHOICE_SIZE_T['uint']
      uint32 :e_flags
      uint16 :e_ehsize # size of this header
      uint16 :e_phentsize # size of each segment
      uint16 :e_phnum # number of segments
      uint16 :e_shentsize # size of each section
      uint16 :e_shnum # number of sections
      uint16 :e_shstrndx # index of string table section
    end

    # Section header structure.
    class ELF_Shdr < ELFStruct
      endian :big_and_little
      uint32 :sh_name
      uint32 :sh_type
      choice :sh_flags, **CHOICE_SIZE_T['uint']
      choice :sh_addr, **CHOICE_SIZE_T['uint']
      choice :sh_offset, **CHOICE_SIZE_T['uint']
      choice :sh_size, **CHOICE_SIZE_T['uint']
      uint32 :sh_link
      uint32 :sh_info
      choice :sh_addralign, **CHOICE_SIZE_T['uint']
      choice :sh_entsize, **CHOICE_SIZE_T['uint']
    end

    # Program header structure for 32-bit.
    class ELF32_Phdr < ELFStruct
      endian :big_and_little
      uint32 :p_type
      uint32 :p_offset
      uint32 :p_vaddr
      uint32 :p_paddr
      uint32 :p_filesz
      uint32 :p_memsz
      uint32 :p_flags
      uint32 :p_align
    end

    # Program header structure for 64-bit.
    class ELF64_Phdr < ELFStruct
      endian :big_and_little
      uint32 :p_type
      uint32 :p_flags
      uint64 :p_offset
      uint64 :p_vaddr
      uint64 :p_paddr
      uint64 :p_filesz
      uint64 :p_memsz
      uint64 :p_align
    end

    # Gets the class of program header according to bits.
    ELF_Phdr = {
      32 => ELF32_Phdr,
      64 => ELF64_Phdr
    }.freeze

    # Symbol structure for 32-bit.
    class ELF32_sym < ELFStruct
      endian :big_and_little
      uint32 :st_name
      uint32 :st_value
      uint32 :st_size
      uint8 :st_info
      uint8 :st_other
      uint16 :st_shndx
    end

    # Symbol structure for 64-bit.
    class ELF64_sym < ELFStruct
      endian :big_and_little
      uint32 :st_name  # Symbol name, index in string tbl
      uint8 :st_info   # Type and binding attributes
      uint8 :st_other  # No defined meaning, 0
      uint16 :st_shndx # Associated section index
      uint64 :st_value # Value of the symbol
      uint64 :st_size  # Associated symbol size
    end

    # Get symbol header class according to bits.
    ELF_sym = {
      32 => ELF32_sym,
      64 => ELF64_sym
    }.freeze

    # Note header.
    class ELF_Nhdr < ELFStruct
      endian :big_and_little
      uint32 :n_namesz # Name size
      uint32 :n_descsz # Content size
      uint32 :n_type   # Content type
    end

    # Dynamic tag header.
    class ELF_Dyn < ELFStruct
      endian :big_and_little
      choice :d_tag, **CHOICE_SIZE_T['int']
      # This is an union type named +d_un+ in original source,
      # simplify it to be +d_val+ here.
      choice :d_val, **CHOICE_SIZE_T['uint']
    end

    # Rel header in .rel section.
    class ELF_Rel < ELFStruct
      endian :big_and_little
      choice :r_offset, **CHOICE_SIZE_T['uint']
      choice :r_info, **CHOICE_SIZE_T['uint']

      # Compatibility with ELF_Rela, both can be used interchangeably
      def r_addend
        nil
      end
    end

    # Rela header in .rela section.
    class ELF_Rela < ELFStruct
      endian :big_and_little
      choice :r_offset, **CHOICE_SIZE_T['uint']
      choice :r_info, **CHOICE_SIZE_T['uint']
      choice :r_addend, **CHOICE_SIZE_T['int']
    end
  end
end
