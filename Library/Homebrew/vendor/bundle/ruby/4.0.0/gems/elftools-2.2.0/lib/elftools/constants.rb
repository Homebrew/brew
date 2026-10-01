# frozen_string_literal: true

require 'elftools/constants/machine'
require 'elftools/constants/relocation'

module ELFTools
  # Define constants from elf.h.
  # Mostly refer from https://github.com/torvalds/linux/blob/master/include/uapi/linux/elf.h
  # and binutils/elfcpp/elfcpp.h.
  module Constants
    # ELF magic header
    ELFMAG = "\x7FELF"

    # Names a value after the constants that define it, for the modules where
    # several of them may define one value.
    #
    # A machine defines names of its own, and a name may mark where a range of
    # values begins or ends, or how many of them are defined, rather than name
    # one of them.
    module Naming
      # Architectures a constant can be named after, the longest first so that
      # a name is read as the architecture it spells out in full.
      ARCHITECTURES = (R.constants - [:MACHINES]).sort_by { |name| -name.length }.freeze

      # Return the name of +value+.
      #
      # Names of a machine other than +machine+ are passed over, as are the
      # ones that mark a range or a count instead of naming a value.
      # @param [Integer?] machine Value of +e_machine+.
      # @param [Integer] value The value to name.
      # @return [String] The name.
      # @example
      #   Constants::STT.mapping(Constants::EM_ARM, 13)
      #   #=> 'STT_ARM_TFUNC'
      #   Constants::STT.mapping(Constants::EM_X86_64, 13)
      #   #=> '<unknown>: 0xd'
      def mapping(machine, value)
        architecture = R::MACHINES[machine]
        name = names_by_value.fetch(value, []).find do |constant|
          !marker?(constant) && [nil, architecture].include?(architecture_of(constant))
        end
        name ? name.to_s : format('<unknown>: 0x%x', value)
      end

      private

      # The constants defining each value, in the order they are defined.
      # @return [Hash{Integer => Array<Symbol>}] The constants.
      def names_by_value
        @names_by_value ||= constants.group_by { |constant| const_get(constant) }
      end

      # The architecture a constant is named after.
      # @example
      #   architecture_of(:SHN_MIPS_ACOMMON)
      #   #=> :MIPS
      #   architecture_of(:SHN_ABS)
      #   #=> nil
      # @return [Symbol?] The architecture, +nil+ if the name spells out none.
      def architecture_of(constant)
        rest = constant.to_s.sub(/\A#{name.split('::').last}_/, '')
        ARCHITECTURES.find { |architecture| rest.start_with?("#{architecture}_") }
      end

      # Whether a constant marks where a range of values begins or ends, or
      # how many of them are defined, rather than naming one of them.
      # @example
      #   marker?(:STT_LOPROC)
      #   #=> true
      #   marker?(:STT_FUNC)
      #   #=> false
      # @return [Boolean] The answer.
      def marker?(constant)
        constant.to_s.match?(/_((LO|HI)(OS|PROC|RESERVE)|NUM)\z/)
      end
    end

    # Values of `d_un.d_val' in the DT_FLAGS and DT_FLAGS_1 entry.
    module DF
      DF_ORIGIN       = 0x00000001 # Object may use DF_ORIGIN
      DF_SYMBOLIC     = 0x00000002 # Symbol resolutions starts here
      DF_TEXTREL      = 0x00000004 # Object contains text relocations
      DF_BIND_NOW     = 0x00000008 # No lazy binding for this object
      DF_STATIC_TLS   = 0x00000010 # Module uses the static TLS model

      DF_1_NOW        = 0x00000001 # Set RTLD_NOW for this object.
      DF_1_GLOBAL     = 0x00000002 # Set RTLD_GLOBAL for this object.
      DF_1_GROUP      = 0x00000004 # Set RTLD_GROUP for this object.
      DF_1_NODELETE   = 0x00000008 # Set RTLD_NODELETE for this object.
      DF_1_LOADFLTR   = 0x00000010 # Trigger filtee loading at runtime.
      DF_1_INITFIRST  = 0x00000020 # Set RTLD_INITFIRST for this object
      DF_1_NOOPEN     = 0x00000040 # Set RTLD_NOOPEN for this object.
      DF_1_ORIGIN     = 0x00000080 # $ORIGIN must be handled.
      DF_1_DIRECT     = 0x00000100 # Direct binding enabled.
      DF_1_TRANS      = 0x00000200 # :nodoc:
      DF_1_INTERPOSE  = 0x00000400 # Object is used to interpose.
      DF_1_NODEFLIB   = 0x00000800 # Ignore default lib search path.
      DF_1_NODUMP     = 0x00001000 # Object can't be dldump'ed.
      DF_1_CONFALT    = 0x00002000 # Configuration alternative created.
      DF_1_ENDFILTEE  = 0x00004000 # Filtee terminates filters search.
      DF_1_DISPRELDNE = 0x00008000 # Disp reloc applied at build time.
      DF_1_DISPRELPND = 0x00010000 # Disp reloc applied at run-time.
      DF_1_NODIRECT   = 0x00020000 # Object has no-direct binding.
      DF_1_IGNMULDEF  = 0x00040000 # :nodoc:
      DF_1_NOKSYMS    = 0x00080000 # :nodoc:
      DF_1_NOHDR      = 0x00100000 # :nodoc:
      DF_1_EDITED     = 0x00200000 # Object is modified after built.
      DF_1_NORELOC    = 0x00400000 # :nodoc:
      DF_1_SYMINTPOSE = 0x00800000 # Object has individual interposers.
      DF_1_GLOBAUDIT  = 0x01000000 # Global auditing required.
      DF_1_SINGLETON  = 0x02000000 # Singleton symbols are used.
      DF_1_STUB       = 0x04000000 # :nodoc:
      DF_1_PIE        = 0x08000000 # Object is a position-independent executable.
      DF_1_KMOD       = 0x10000000 # :nodoc:
      DF_1_WEAKFILTER = 0x20000000 # :nodoc:
      DF_1_NOCOMMON   = 0x40000000 # :nodoc:
    end
    include DF

    # Dynamic table types, records in +d_tag+.
    module DT
      extend Naming

      DT_NULL                       = 0 # marks the end of the _DYNAMIC array
      DT_NEEDED                     = 1 # libraries need to be linked by loader
      DT_PLTRELSZ                   = 2 # total size of relocation entries
      DT_PLTGOT                     = 3 # address of procedure linkage table or global offset table
      DT_HASH                       = 4 # address of symbol hash table
      DT_STRTAB                     = 5 # address of string table
      DT_SYMTAB                     = 6 # address of symbol table
      DT_RELA                       = 7 # address of a relocation table
      DT_RELASZ                     = 8 # total size of the {DT_RELA} table
      DT_RELAENT                    = 9 # size of each entry in the {DT_RELA} table
      DT_STRSZ                      = 10 # total size of {DT_STRTAB}
      DT_SYMENT                     = 11 # size of each entry in {DT_SYMTAB}
      DT_INIT                       = 12 # where the initialization function is
      DT_FINI                       = 13 # where the termination function is
      DT_SONAME                     = 14 # the shared object name
      DT_RPATH                      = 15 # has been superseded by {DT_RUNPATH}
      DT_SYMBOLIC                   = 16 # has been superseded by the DF_SYMBOLIC flag
      DT_REL                        = 17 # similar to {DT_RELA}
      DT_RELSZ                      = 18 # total size of the {DT_REL} table
      DT_RELENT                     = 19 # size of each entry in the {DT_REL} table
      DT_PLTREL                     = 20 # type of relocation entry, either {DT_REL} or {DT_RELA}
      DT_DEBUG                      = 21 # for debugging
      DT_TEXTREL                    = 22 # has been superseded by the DF_TEXTREL flag
      DT_JMPREL                     = 23 # address of relocation entries associated solely with procedure linkage table
      DT_BIND_NOW                   = 24 # if the loader needs to do relocate now, superseded by the DF_BIND_NOW flag
      DT_INIT_ARRAY                 = 25 # address init array
      DT_FINI_ARRAY                 = 26 # address of fini array
      DT_INIT_ARRAYSZ               = 27 # total size of init array
      DT_FINI_ARRAYSZ               = 28 # total size of fini array
      DT_RUNPATH                    = 29 # path of libraries for searching
      DT_FLAGS                      = 30 # flags
      DT_ENCODING                   = 32 # just a lower bound
      DT_PREINIT_ARRAY              = 32 # pre-initialization functions array
      DT_PREINIT_ARRAYSZ            = 33 # pre-initialization functions array size (bytes)
      DT_SYMTAB_SHNDX               = 34 # address of the +SHT_SYMTAB_SHNDX+ section associated with {DT_SYMTAB} table
      DT_RELRSZ                     = 35 # :nodoc:
      DT_RELR                       = 36 # :nodoc:
      DT_RELRENT                    = 37 # :nodoc:

      # Values between {DT_LOOS} and {DT_HIOS} are reserved for operating system-specific semantics.
      DT_LOOS                       = 0x6000000d
      DT_HIOS                       = 0x6ffff000 # see {DT_LOOS}

      # Values between {DT_VALRNGLO} and {DT_VALRNGHI} use the +d_un.d_val+ field of the dynamic structure.
      DT_VALRNGLO                   = 0x6ffffd00
      DT_VALRNGHI                   = 0x6ffffdff # see {DT_VALRNGLO}

      # Values between {DT_ADDRRNGLO} and {DT_ADDRRNGHI} use the +d_un.d_ptr+ field of the dynamic structure.
      DT_ADDRRNGLO                  = 0x6ffffe00
      DT_GNU_HASH                   = 0x6ffffef5 # the gnu hash
      DT_TLSDESC_PLT                = 0x6ffffef6 # :nodoc:
      DT_TLSDESC_GOT                = 0x6ffffef7 # :nodoc:
      DT_GNU_CONFLICT               = 0x6ffffef8 # :nodoc:
      DT_GNU_LIBLIST                = 0x6ffffef9 # :nodoc:
      DT_CONFIG                     = 0x6ffffefa # :nodoc:
      DT_DEPAUDIT                   = 0x6ffffefb # :nodoc:
      DT_AUDIT                      = 0x6ffffefc # :nodoc:
      DT_PLTPAD                     = 0x6ffffefd # :nodoc:
      DT_MOVETAB                    = 0x6ffffefe # :nodoc:
      DT_SYMINFO                    = 0x6ffffeff # :nodoc:
      DT_ADDRRNGHI                  = 0x6ffffeff # see {DT_ADDRRNGLO}

      DT_VERSYM                     = 0x6ffffff0 # section address of .gnu.version
      DT_RELACOUNT                  = 0x6ffffff9 # relative relocation count
      DT_RELCOUNT                   = 0x6ffffffa # relative relocation count
      DT_FLAGS_1                    = 0x6ffffffb # flags
      DT_VERDEF                     = 0x6ffffffc # address of version definition table
      DT_VERDEFNUM                  = 0x6ffffffd # number of entries in {DT_VERDEF}
      DT_VERNEED                    = 0x6ffffffe # address of version dependency table
      DT_VERNEEDNUM                 = 0x6fffffff # number of entries in {DT_VERNEED}

      # Values between {DT_LOPROC} and {DT_HIPROC} are reserved for processor-specific semantics.
      DT_LOPROC                     = 0x70000000

      DT_PPC_GOT                    = 0x70000000 # global offset table
      DT_PPC_OPT                    = 0x70000001 # whether various optimisations are possible

      DT_PPC64_GLINK                = 0x70000000 # start of the .glink section
      DT_PPC64_OPD                  = 0x70000001 # start of the .opd section
      DT_PPC64_OPDSZ                = 0x70000002 # size of the .opd section
      DT_PPC64_OPT                  = 0x70000003 # whether various optimisations are possible

      DT_SPARC_REGISTER             = 0x70000000 # index of an +STT_SPARC_REGISTER+ symbol within the {DT_SYMTAB} table

      DT_MIPS_RLD_VERSION           = 0x70000001 # 32 bit version number for runtime linker interface
      DT_MIPS_TIME_STAMP            = 0x70000002 # time stamp
      DT_MIPS_ICHECKSUM             = 0x70000003 # checksum of external strings and common sizes
      DT_MIPS_IVERSION              = 0x70000004 # index of version string in string table
      DT_MIPS_FLAGS                 = 0x70000005 # 32 bits of flags
      DT_MIPS_BASE_ADDRESS          = 0x70000006 # base address of the segment
      DT_MIPS_MSYM                  = 0x70000007 # :nodoc:
      DT_MIPS_CONFLICT              = 0x70000008 # address of +.conflict+ section
      DT_MIPS_LIBLIST               = 0x70000009 # address of +.liblist+ section
      DT_MIPS_LOCAL_GOTNO           = 0x7000000a # number of local global offset table entries
      DT_MIPS_CONFLICTNO            = 0x7000000b # number of entries in the +.conflict+ section
      DT_MIPS_LIBLISTNO             = 0x70000010 # number of entries in the +.liblist+ section
      DT_MIPS_SYMTABNO              = 0x70000011 # number of entries in the +.dynsym+ section
      DT_MIPS_UNREFEXTNO            = 0x70000012 # index of first external dynamic symbol not referenced locally
      DT_MIPS_GOTSYM                = 0x70000013 # index of first dynamic symbol in global offset table
      DT_MIPS_HIPAGENO              = 0x70000014 # number of page table entries in global offset table
      DT_MIPS_RLD_MAP               = 0x70000016 # address of run time loader map, used for debugging
      DT_MIPS_DELTA_CLASS           = 0x70000017 # delta C++ class definition
      DT_MIPS_DELTA_CLASS_NO        = 0x70000018 # number of entries in {DT_MIPS_DELTA_CLASS}
      DT_MIPS_DELTA_INSTANCE        = 0x70000019 # delta C++ class instances
      DT_MIPS_DELTA_INSTANCE_NO     = 0x7000001a # number of entries in {DT_MIPS_DELTA_INSTANCE}
      DT_MIPS_DELTA_RELOC           = 0x7000001b # delta relocations
      DT_MIPS_DELTA_RELOC_NO        = 0x7000001c # number of entries in {DT_MIPS_DELTA_RELOC}
      DT_MIPS_DELTA_SYM             = 0x7000001d # delta symbols that Delta relocations refer to
      DT_MIPS_DELTA_SYM_NO          = 0x7000001e # number of entries in {DT_MIPS_DELTA_SYM}
      DT_MIPS_DELTA_CLASSSYM        = 0x70000020 # delta symbols that hold class declarations
      DT_MIPS_DELTA_CLASSSYM_NO     = 0x70000021 # number of entries in {DT_MIPS_DELTA_CLASSSYM}
      DT_MIPS_CXX_FLAGS             = 0x70000022 # flags indicating information about C++ flavor
      DT_MIPS_PIXIE_INIT            = 0x70000023 # :nodoc:
      DT_MIPS_SYMBOL_LIB            = 0x70000024 # address of +.MIPS.symlib+
      DT_MIPS_LOCALPAGE_GOTIDX      = 0x70000025 # GOT index of the first PTE for a segment
      DT_MIPS_LOCAL_GOTIDX          = 0x70000026 # GOT index of the first PTE for a local symbol
      DT_MIPS_HIDDEN_GOTIDX         = 0x70000027 # GOT index of the first PTE for a hidden symbol
      DT_MIPS_PROTECTED_GOTIDX      = 0x70000028 # GOT index of the first PTE for a protected symbol
      DT_MIPS_OPTIONS               = 0x70000029 # address of +.MIPS.options+
      DT_MIPS_INTERFACE             = 0x7000002a # address of +.interface+
      DT_MIPS_DYNSTR_ALIGN          = 0x7000002b # :nodoc:
      DT_MIPS_INTERFACE_SIZE        = 0x7000002c # size of the +.interface+ section
      DT_MIPS_RLD_TEXT_RESOLVE_ADDR = 0x7000002d # size of +rld_text_resolve+ function stored in the GOT
      DT_MIPS_PERF_SUFFIX           = 0x7000002e # default suffix of DSO to be added by rld on +dlopen()+ calls
      DT_MIPS_COMPACT_SIZE          = 0x7000002f # size of compact relocation section (O32)
      DT_MIPS_GP_VALUE              = 0x70000030 # GP value for auxiliary GOTs
      DT_MIPS_AUX_DYNAMIC           = 0x70000031 # address of auxiliary +.dynamic+
      DT_MIPS_PLTGOT                = 0x70000032 # address of the base of the PLTGOT
      DT_MIPS_RWPLT                 = 0x70000034 # base of a writable PLT
      DT_MIPS_RLD_MAP_REL           = 0x70000035 # relative offset of run time loader map
      DT_MIPS_XHASH                 = 0x70000036 # GNU-style hash table with xlat

      DT_AUXILIARY                  = 0x7ffffffd # :nodoc:
      DT_USED                       = 0x7ffffffe # :nodoc:
      DT_FILTER                     = 0x7ffffffe # :nodoc:

      DT_HIPROC                     = 0x7fffffff # see {DT_LOPROC}
    end
    include DT

    # These constants define the various ELF target machines.
    #
    # Constants are defined in +elftools/constants/machine+.
    module EM
      # Names are only loaded when a name is asked for.
      autoload :NAMES, 'elftools/constants/machine_names'

      # Return the architecture name according to +val+.
      # Used by {ELFTools::ELFFile#machine}.
      # @param [Integer] val Value of +e_machine+.
      # @return [String]
      #   Name of architecture.
      # @example
      #   mapping(3)
      #   #=> 'Intel 80386'
      #   mapping(62)
      #   #=> 'Advanced Micro Devices X86-64 processor'
      #   mapping(243)
      #   #=> 'RISC-V'
      #   mapping(1337)
      #   #=> '<unknown>: 0x539'
      def self.mapping(val)
        NAMES.fetch(val) { format('<unknown>: 0x%x', val) }
      end
    end
    include EM

    # Flags of a version, recorded in the +vd_flags+ of a definition and the
    # +vna_flags+ of a requirement.
    module VER_FLG
      VER_FLG_BASE = 0x1 # The version the file itself is, rather than one of the versions it defines
      VER_FLG_WEAK = 0x2 # A version no symbol is bound to
      VER_FLG_INFO = 0x4 # A version recorded for information rather than to be matched
    end
    include VER_FLG

    # The indices a symbol names a version with that name no version.
    module VER_NDX
      VER_NDX_LOCAL = 0 # A symbol of the file itself, which nothing outside it binds to
      VER_NDX_GLOBAL = 1 # A symbol of no version at all
      VER_NDX_HIDDEN = 0x8000 # Not an index but a bit of one, marking a version that is not the default
    end
    include VER_NDX

    # Relocation types, see +elftools/constants/relocation+ for the constants.
    module R
      # Return the name of a relocation type.
      #
      # A type only means something together with the machine that recorded it,
      # both of them are needed to name it.
      # @param [Integer?] machine Value of +e_machine+.
      # @param [Integer] type The relocation type.
      # @return [String] Name of the relocation type.
      # @example
      #   mapping(Constants::EM_X86_64, 7)
      #   #=> 'R_X86_64_JUMP_SLOT'
      #   mapping(Constants::EM_ARM, 7)
      #   #=> 'R_ARM_THM_ABS5'
      #   mapping(Constants::EM_X86_64, 1337)
      #   #=> '<unknown>: 0x539'
      def self.mapping(machine, type)
        architecture = MACHINES[machine]
        names = architecture && names_of(const_get(architecture))
        names&.fetch(type, nil) || format('<unknown>: 0x%x', type)
      end

      # The type a machine calls a relocation that only adds the load bias,
      # which every architecture defining one spells +R_<arch>_RELATIVE+.
      #
      # A table of them recorded as +DT_RELR+ names no type, because the
      # format holds nothing but addresses and every one of them relocates
      # this way, so the type is asked of the machine instead.
      # @param [Integer?] machine Value of +e_machine+.
      # @return [Integer, nil]
      #   The type, +nil+ if the machine names no such relocation.
      # @example
      #   relative(Constants::EM_X86_64)
      #   #=> 8 # R_X86_64_RELATIVE
      #   relative(Constants::EM_AARCH64)
      #   #=> 1027 # R_AARCH64_RELATIVE, not the R_AARCH64_P32_RELATIVE of ILP32
      def self.relative(machine)
        architecture = MACHINES[machine]
        return if architecture.nil?

        @relative ||= {}
        @relative.fetch(architecture) do
          names = const_get(architecture).constants.grep(/_RELATIVE\z/)
          # An architecture naming more than one names the other for a second
          # data model, which spells it out in the name and so is longer.
          @relative[architecture] = names.min_by(&:length)&.then { |name| const_get(architecture).const_get(name) }
        end
      end

      # Names of every relocation type an architecture defines.
      # @return [Hash{Integer => String}]
      def self.names_of(architecture)
        @names_of ||= {}
        @names_of[architecture] ||= architecture.constants.to_h { |name| [architecture.const_get(name), name.to_s] }
      end
    end

    # This module defines ELF file types.
    module ET
      ET_NONE = 0 # no file type
      ET_REL  = 1 # relocatable file
      ET_EXEC = 2 # executable file
      ET_DYN  = 3 # shared object
      ET_CORE = 4 # core file
      # Return the type name according to +e_type+ in ELF file header.
      # @return [String] Type in string format.
      def self.mapping(type)
        case type
        when Constants::ET_NONE then 'NONE'
        when Constants::ET_REL then 'REL'
        when Constants::ET_EXEC then 'EXEC'
        when Constants::ET_DYN then 'DYN'
        when Constants::ET_CORE then 'CORE'
        else '<unknown>'
        end
      end
    end
    include ET

    # Program header permission flags, records bitwise OR value in +p_flags+.
    module PF
      PF_X = 1 # executable
      PF_W = 2 # writable
      PF_R = 4 # readable
    end
    include PF

    # Program header types, records in +p_type+.
    module PT
      PT_NULL              = 0          # null segment
      PT_LOAD              = 1          # segment to be load
      PT_DYNAMIC           = 2          # dynamic tags
      PT_INTERP            = 3          # interpreter, same as .interp section
      PT_NOTE              = 4          # same as .note* section
      PT_SHLIB             = 5          # reserved
      PT_PHDR              = 6          # where program header starts
      PT_TLS               = 7          # thread local storage segment

      PT_LOOS              = 0x60000000 # OS-specific
      PT_GNU_EH_FRAME      = 0x6474e550 # for exception handler
      PT_GNU_STACK         = 0x6474e551 # permission of stack
      PT_GNU_RELRO         = 0x6474e552 # read only after relocation
      PT_GNU_PROPERTY      = 0x6474e553 # GNU property
      PT_GNU_MBIND_HI      = 0x6474f554 # Mbind segments (upper bound)
      PT_GNU_MBIND_LO      = 0x6474e555 # Mbind segments (lower bound)
      PT_OPENBSD_RANDOMIZE = 0x65a3dbe6 # Fill with random data
      PT_OPENBSD_WXNEEDED  = 0x65a3dbe7 # Program does W^X violations
      PT_OPENBSD_BOOTDATA  = 0x65a41be6 # Section for boot arguments
      PT_HIOS              = 0x6fffffff # OS-specific

      # Values between {PT_LOPROC} and {PT_HIPROC} are reserved for processor-specific semantics.
      PT_LOPROC            = 0x70000000

      PT_ARM_ARCHEXT       = 0x70000000 # platform architecture compatibility information
      PT_ARM_EXIDX         = 0x70000001 # exception unwind tables

      PT_MIPS_REGINFO      = 0x70000000 # register usage information
      PT_MIPS_RTPROC       = 0x70000001 # runtime procedure table
      PT_MIPS_OPTIONS      = 0x70000002 # +.MIPS.options+ section
      PT_MIPS_ABIFLAGS     = 0x70000003 # +.MIPS.abiflags+ section

      PT_AARCH64_ARCHEXT   = 0x70000000 # platform architecture compatibility information
      PT_AARCH64_UNWIND    = 0x70000001 # exception unwind tables

      PT_S390_PGSTE        = 0x70000000 # 4k page table size

      PT_HIPROC            = 0x7fffffff # see {PT_LOPROC}
    end
    include PT

    # Special indices to section. These are used when there is no valid index to section header.
    # The meaning of these values is left upto the embedding header.
    module SHN
      extend Naming

      SHN_UNDEF           = 0      # undefined section
      SHN_LORESERVE       = 0xff00 # start of reserved indices

      # Values between {SHN_LOPROC} and {SHN_HIPROC} are reserved for processor-specific semantics.
      SHN_LOPROC          = 0xff00

      SHN_MIPS_ACOMMON    = 0xff00 # defined and allocated common symbol
      SHN_MIPS_TEXT       = 0xff01 # defined and allocated text symbol
      SHN_MIPS_DATA       = 0xff02 # defined and allocated data symbol
      SHN_MIPS_SCOMMON    = 0xff03 # small common symbol
      SHN_MIPS_SUNDEFINED = 0xff04 # small undefined symbol

      SHN_X86_64_LCOMMON  = 0xff02 # large common symbol

      SHN_HIPROC          = 0xff1f # see {SHN_LOPROC}

      # Values between {SHN_LOOS} and {SHN_HIOS} are reserved for operating system-specific semantics.
      SHN_LOOS            = 0xff20
      SHN_HIOS            = 0xff3f # see {SHN_LOOS}
      SHN_ABS             = 0xfff1 # specifies absolute values for the corresponding reference
      SHN_COMMON          = 0xfff2 # symbols defined relative to this section are common symbols
      SHN_XINDEX          = 0xffff # escape value indicating that the actual section header index is too large to fit
      SHN_HIRESERVE       = 0xffff # end of reserved indices
    end
    include SHN

    # The escape value the ELF header records where it cannot hold a count of
    # the program headers, which is then recorded in the first section header.
    module PN
      extend Naming

      PN_XNUM = 0xffff # the number of program headers is too large for the header to hold
    end
    include PN

    # Section flag mask types, records in +sh_flag+.
    module SHF
      SHF_WRITE = (1 << 0) # Writable
      SHF_ALLOC = (1 << 1) # Occupies memory during execution
      SHF_EXECINSTR = (1 << 2) # Executable
      SHF_MERGE = (1 << 4) # Might be merged
      SHF_STRINGS = (1 << 5) # Contains nul-terminated strings
      SHF_INFO_LINK = (1 << 6) # `sh_info' contains SHT index
      SHF_LINK_ORDER = (1 << 7) # Preserve order after combining
      SHF_OS_NONCONFORMING = (1 << 8) # Non-standard OS specific handling required
      SHF_GROUP = (1 << 9) # Section is member of a group.
      SHF_TLS = (1 << 10) # Section hold thread-local data.
      SHF_COMPRESSED = (1 << 11) # Section with compressed data.
      SHF_MASKOS = 0x0ff00000 # OS-specific.
      SHF_MASKPROC = 0xf0000000 # Processor-specific
      SHF_GNU_RETAIN = (1 << 21) # Not to be GCed by linker.
      SHF_GNU_MBIND = (1 << 24) # Mbind section
      SHF_ORDERED = (1 << 30) # Special ordering requirement
      SHF_EXCLUDE = (1 << 31) # Section is excluded unless referenced or allocated (Solaris).
    end
    include SHF

    # Section header types, records in +sh_type+.
    module SHT
      SHT_NULL                    = 0 # null section
      SHT_PROGBITS                = 1 # information defined by program itself
      SHT_SYMTAB                  = 2 # symbol table section
      SHT_STRTAB                  = 3 # string table section
      SHT_RELA                    = 4 # relocation with addends
      SHT_HASH                    = 5 # symbol hash table
      SHT_DYNAMIC                 = 6 # information of dynamic linking
      SHT_NOTE                    = 7 # section for notes
      SHT_NOBITS                  = 8 # section occupies no space
      SHT_REL                     = 9 # relocation
      SHT_SHLIB                   = 10 # reserved
      SHT_DYNSYM                  = 11 # symbols for dynamic
      SHT_INIT_ARRAY              = 14 # array of initialization functions
      SHT_FINI_ARRAY              = 15 # array of termination functions
      SHT_PREINIT_ARRAY           = 16 # array of functions that are invoked before all other initialization functions
      SHT_GROUP                   = 17 # section group
      SHT_SYMTAB_SHNDX            = 18 # indices for SHN_XINDEX entries
      SHT_RELR                    = 19 # RELR relative relocations

      # Values between {SHT_LOOS} and {SHT_HIOS} are reserved for operating system-specific semantics.
      SHT_LOOS                    = 0x60000000
      SHT_GNU_INCREMENTAL_INPUTS  = 0x6fff4700 # incremental build data
      SHT_GNU_INCREMENTAL_SYMTAB  = 0x6fff4701 # incremental build data
      SHT_GNU_INCREMENTAL_RELOCS  = 0x6fff4702 # incremental build data
      SHT_GNU_INCREMENTAL_GOT_PLT = 0x6fff4703 # incremental build data
      SHT_GNU_ATTRIBUTES          = 0x6ffffff5 # object attributes
      SHT_GNU_HASH                = 0x6ffffff6 # GNU style symbol hash table
      SHT_GNU_LIBLIST             = 0x6ffffff7 # list of prelink dependencies
      SHT_SUNW_verdef             = 0x6ffffffd # versions defined by file
      SHT_GNU_verdef              = 0x6ffffffd # versions defined by file
      SHT_SUNW_verneed            = 0x6ffffffe # versions needed by file
      SHT_GNU_verneed             = 0x6ffffffe # versions needed by file
      SHT_SUNW_versym             = 0x6fffffff # symbol versions
      SHT_GNU_versym              = 0x6fffffff # symbol versions
      SHT_HIOS                    = 0x6fffffff # see {SHT_LOOS}

      # Values between {SHT_LOPROC} and {SHT_HIPROC} are reserved for processor-specific semantics.
      SHT_LOPROC                  = 0x70000000

      SHT_SPARC_GOTDATA           = 0x70000000 # :nodoc:

      SHT_ARM_EXIDX               = 0x70000001 # exception index table
      SHT_ARM_PREEMPTMAP          = 0x70000002 # BPABI DLL dynamic linking pre-emption map
      SHT_ARM_ATTRIBUTES          = 0x70000003 # object file compatibility attributes
      SHT_ARM_DEBUGOVERLAY        = 0x70000004 # support for debugging overlaid programs
      SHT_ARM_OVERLAYSECTION      = 0x70000005 # support for debugging overlaid programs

      SHT_X86_64_UNWIND           = 0x70000001 # x86_64 unwind information

      SHT_MIPS_LIBLIST            = 0x70000000 # set of dynamic shared objects
      SHT_MIPS_MSYM               = 0x70000001 # :nodoc:
      SHT_MIPS_CONFLICT           = 0x70000002 # list of symbols whose definitions conflict with shared objects
      SHT_MIPS_GPTAB              = 0x70000003 # global pointer table
      SHT_MIPS_UCODE              = 0x70000004 # microcode information
      SHT_MIPS_DEBUG              = 0x70000005 # register usage information
      SHT_MIPS_REGINFO            = 0x70000006 # section contains register usage information
      SHT_MIPS_PACKAGE            = 0x70000007 # :nodoc:
      SHT_MIPS_PACKSYM            = 0x70000008 # :nodoc:
      SHT_MIPS_RELD               = 0x70000009 # :nodoc:
      SHT_MIPS_IFACE              = 0x7000000b # interface information
      SHT_MIPS_CONTENT            = 0x7000000c # description of contents of another section
      SHT_MIPS_OPTIONS            = 0x7000000d # miscellaneous options
      SHT_MIPS_SHDR               = 0x70000010 # :nodoc:
      SHT_MIPS_FDESC              = 0x70000011 # :nodoc:
      SHT_MIPS_EXTSYM             = 0x70000012 # :nodoc:
      SHT_MIPS_DENSE              = 0x70000013 # :nodoc:
      SHT_MIPS_PDESC              = 0x70000014 # :nodoc:
      SHT_MIPS_LOCSYM             = 0x70000015 # :nodoc:
      SHT_MIPS_AUXSYM             = 0x70000016 # :nodoc:
      SHT_MIPS_OPTSYM             = 0x70000017 # :nodoc:
      SHT_MIPS_LOCSTR             = 0x70000018 # :nodoc:
      SHT_MIPS_LINE               = 0x70000019 # :nodoc:
      SHT_MIPS_RFDESC             = 0x7000001a # :nodoc:
      SHT_MIPS_DELTASYM           = 0x7000001b # delta C++ symbol table
      SHT_MIPS_DELTAINST          = 0x7000001c # delta C++ instance table
      SHT_MIPS_DELTACLASS         = 0x7000001d # delta C++ class table
      SHT_MIPS_DWARF              = 0x7000001e # DWARF debugging section
      SHT_MIPS_DELTADECL          = 0x7000001f # delta C++ declarations
      SHT_MIPS_SYMBOL_LIB         = 0x70000020 # list of libraries the binary depends on
      SHT_MIPS_EVENTS             = 0x70000021 # events section
      SHT_MIPS_TRANSLATE          = 0x70000022 # :nodoc:
      SHT_MIPS_PIXIE              = 0x70000023 # :nodoc:
      SHT_MIPS_XLATE              = 0x70000024 # address translation table
      SHT_MIPS_XLATE_DEBUG        = 0x70000025 # SGI internal address translation table
      SHT_MIPS_WHIRL              = 0x70000026 # intermediate code
      SHT_MIPS_EH_REGION          = 0x70000027 # C++ exception handling region info
      SHT_MIPS_PDR_EXCEPTION      = 0x70000029 # runtime procedure descriptor table exception information
      SHT_MIPS_ABIFLAGS           = 0x7000002a # ABI related flags
      SHT_MIPS_XHASH              = 0x7000002b # GNU style symbol hash table with xlat

      SHT_AARCH64_ATTRIBUTES      = 0x70000003 # :nodoc:

      SHT_CSKY_ATTRIBUTES         = 0x70000001 # object file compatibility attributes

      SHT_ORDERED                 = 0x7fffffff # :nodoc:

      SHT_HIPROC                  = 0x7fffffff # see {SHT_LOPROC}

      # Values between {SHT_LOUSER} and {SHT_HIUSER} are reserved for application programs.
      SHT_LOUSER                  = 0x80000000
      SHT_HIUSER                  = 0xffffffff # see {SHT_LOUSER}
    end
    include SHT

    # Symbol binding from Sym st_info field.
    module STB
      extend Naming

      STB_LOCAL      = 0 # Local symbol
      STB_GLOBAL     = 1 # Global symbol
      STB_WEAK       = 2 # Weak symbol
      STB_NUM        = 3 # Number of defined types.
      STB_LOOS       = 10 # Start of OS-specific
      STB_GNU_UNIQUE = 10 # Unique symbol.
      STB_HIOS       = 12 # End of OS-specific
      STB_LOPROC     = 13 # Start of processor-specific
      STB_HIPROC     = 15 # End of processor-specific
    end
    include STB

    # Symbol types from Sym st_info field.
    module STT
      extend Naming

      STT_NOTYPE         = 0 # Symbol type is unspecified
      STT_OBJECT         = 1 # Symbol is a data object
      STT_FUNC           = 2 # Symbol is a code object
      STT_SECTION        = 3 # Symbol associated with a section
      STT_FILE           = 4 # Symbol's name is file name
      STT_COMMON         = 5 # Symbol is a common data object
      STT_TLS            = 6 # Symbol is thread-local data object
      STT_NUM            = 7 # Deprecated.
      STT_RELC           = 8 # Complex relocation expression
      STT_SRELC          = 9 # Signed Complex relocation expression

      # GNU extension: symbol value points to a function which is called
      # at runtime to determine the final value of the symbol.
      STT_GNU_IFUNC      = 10

      STT_LOOS           = 10 # Start of OS-specific
      STT_HIOS           = 12 # End of OS-specific
      STT_LOPROC         = 13 # Start of processor-specific
      STT_HIPROC         = 15 # End of processor-specific

      # The section type that must be used for register symbols on
      # Sparc. These symbols initialize a global register.
      STT_SPARC_REGISTER = 13

      # ARM: a THUMB function. This is not defined in ARM ELF Specification but
      # used by the GNU tool-chain.
      STT_ARM_TFUNC      = 13
      STT_ARM_16BIT      = 15 # ARM: a THUMB label.
    end
    include STT

    # Symbol visibility from Sym st_other field.
    module STV
      extend Naming

      STV_DEFAULT   = 0 # Visibility is specified by binding type
      STV_INTERNAL  = 1 # OS specific version of {STV_HIDDEN}
      STV_HIDDEN    = 2 # Can only be seen inside currently compilation unit
      STV_PROTECTED = 3 # Symbol is visible but cannot be preempted
    end
    include STV
  end
end
