# frozen_string_literal: true

module ELFTools
  # Define constants from elf.h.
  # Mostly refer from https://github.com/torvalds/linux/blob/master/include/uapi/linux/elf.h
  # and binutils/elfcpp/elfcpp.h.
  module Constants
    # ELF magic header
    ELFMAG = "\x7FELF"

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
    module EM
      EM_NONE            = 0      # none
      EM_M32             = 1      # AT&T WE 32100
      EM_SPARC           = 2      # SPARC
      EM_386             = 3      # Intel 80386
      EM_68K             = 4      # Motorola 68000
      EM_88K             = 5      # Motorola 88000
      EM_486             = 6      # Intel 80486
      EM_860             = 7      # Intel 80860
      EM_MIPS            = 8      # MIPS R3000 (officially, big-endian only)
      EM_S370            = 9      # IBM System/370

      # Next two are historical and binaries and
      # modules of these types will be rejected by Linux.
      EM_MIPS_RS3_LE     = 10     # MIPS R3000 little-endian
      EM_MIPS_RS4_BE     = 10     # MIPS R4000 big-endian

      EM_PARISC          = 15     # HPPA
      EM_VPP500          = 17     # Fujitsu VPP500 (also some older versions of PowerPC)
      EM_SPARC32PLUS     = 18     # Sun's "v8plus"
      EM_960             = 19     # Intel 80960
      EM_PPC             = 20     # PowerPC
      EM_PPC64           = 21     # PowerPC64
      EM_S390            = 22     # IBM S/390
      EM_SPU             = 23     # Cell BE SPU
      EM_V800            = 36     # NEC V800 series
      EM_FR20            = 37     # Fujitsu FR20
      EM_RH32            = 38     # TRW RH32
      EM_RCE             = 39     # Motorola M*Core
      EM_ARM             = 40     # ARM 32 bit
      EM_SH              = 42     # SuperH
      EM_SPARCV9         = 43     # SPARC v9 64-bit
      EM_TRICORE         = 44     # Siemens Tricore embedded processor
      EM_ARC             = 45     # ARC Cores
      EM_H8_300          = 46     # Renesas H8/300
      EM_H8_300H         = 47     # Renesas H8/300H
      EM_H8S             = 48     # Renesas H8S
      EM_H8_500          = 49     # Renesas H8/500H
      EM_IA_64           = 50     # HP/Intel IA-64
      EM_MIPS_X          = 51     # Stanford MIPS-X
      EM_COLDFIRE        = 52     # Motorola Coldfire
      EM_68HC12          = 53     # Motorola M68HC12
      EM_MMA             = 54     # Fujitsu Multimedia Accelerator
      EM_PCP             = 55     # Siemens PCP
      EM_NCPU            = 56     # Sony nCPU embedded RISC processor
      EM_NDR1            = 57     # Denso NDR1 microprocessor
      EM_STARCORE        = 58     # Motorola Star*Core processor
      EM_ME16            = 59     # Toyota ME16 processor
      EM_ST100           = 60     # STMicroelectronics ST100 processor
      EM_TINYJ           = 61     # Advanced Logic Corp. TinyJ embedded processor
      EM_X86_64          = 62     # AMD x86-64
      EM_PDSP            = 63     # Sony DSP Processor
      EM_PDP10           = 64     # Digital Equipment Corp. PDP-10
      EM_PDP11           = 65     # Digital Equipment Corp. PDP-11
      EM_FX66            = 66     # Siemens FX66 microcontroller
      EM_ST9PLUS         = 67     # STMicroelectronics ST9+ 8/16 bit microcontroller
      EM_ST7             = 68     # STMicroelectronics ST7 8-bit microcontroller
      EM_68HC16          = 69     # Motorola MC68HC16 Microcontroller
      EM_68HC11          = 70     # Motorola MC68HC11 Microcontroller
      EM_68HC08          = 71     # Motorola MC68HC08 Microcontroller
      EM_68HC05          = 72     # Motorola MC68HC05 Microcontroller
      EM_SVX             = 73     # Silicon Graphics SVx
      EM_ST19            = 74     # STMicroelectronics ST19 8-bit cpu
      EM_VAX             = 75     # Digital VAX
      EM_CRIS            = 76     # Axis Communications 32-bit embedded processor
      EM_JAVELIN         = 77     # Infineon Technologies 32-bit embedded cpu
      EM_FIREPATH        = 78     # Element 14 64-bit DSP processor
      EM_ZSP             = 79     # LSI Logic's 16-bit DSP processor
      EM_MMIX            = 80     # Donald Knuth's educational 64-bit processor
      EM_HUANY           = 81     # Harvard's machine-independent format
      EM_PRISM           = 82     # SiTera Prism
      EM_AVR             = 83     # Atmel AVR 8-bit microcontroller
      EM_FR30            = 84     # Fujitsu FR30
      EM_D10V            = 85     # Mitsubishi D10V
      EM_D30V            = 86     # Mitsubishi D30V
      EM_V850            = 87     # Renesas V850
      EM_M32R            = 88     # Renesas M32R
      EM_MN10300         = 89     # Matsushita MN10300
      EM_MN10200         = 90     # Matsushita MN10200
      EM_PJ              = 91     # picoJava
      EM_OPENRISC        = 92     # OpenRISC 32-bit embedded processor
      EM_ARC_COMPACT     = 93     # ARC International ARCompact processor
      EM_XTENSA          = 94     # Tensilica Xtensa Architecture
      EM_VIDEOCORE       = 95     # Alphamosaic VideoCore processor
      EM_TMM_GPP         = 96     # Thompson Multimedia General Purpose Processor
      EM_NS32K           = 97     # National Semiconductor 32000 series
      EM_TPC             = 98     # Tenor Network TPC processor
      EM_SNP1K           = 99     # Trebia SNP 1000 processor
      EM_ST200           = 100    # STMicroelectronics ST200 microcontroller
      EM_IP2K            = 101    # Ubicom IP2022 micro controller
      EM_MAX             = 102    # MAX Processor
      EM_CR              = 103    # National Semiconductor CompactRISC
      EM_F2MC16          = 104    # Fujitsu F2MC16
      EM_MSP430          = 105    # TI msp430 micro controller
      EM_BLACKFIN        = 106    # ADI Blackfin Processor
      EM_SE_C33          = 107    # S1C33 Family of Seiko Epson processors
      EM_SEP             = 108    # Sharp embedded microprocessor
      EM_ARCA            = 109    # Arca RISC Microprocessor
      EM_UNICORE         = 110    # Microprocessor series from PKU-Unity Ltd. and MPRC of Peking University
      EM_EXCESS          = 111    # eXcess: 16/32/64-bit configurable embedded CPU
      EM_DXP             = 112    # Icera Semiconductor Inc. Deep Execution Processor
      EM_ALTERA_NIOS2    = 113    # Altera Nios II soft-core processor
      EM_CRX             = 114    # National Semiconductor CRX
      EM_XGATE           = 115    # Motorola XGATE embedded processor
      EM_C116            = 116    # Infineon C16x/XC16x processor
      EM_M16C            = 117    # Renesas M16C series microprocessors
      EM_DSPIC30F        = 118    # Microchip Technology dsPIC30F Digital Signal Controller
      EM_CE              = 119    # Freescale Communication Engine RISC core
      EM_M32C            = 120    # Freescale Communication Engine RISC core
      EM_TSK3000         = 131    # Altium TSK3000 core
      EM_RS08            = 132    # Freescale RS08 embedded processor
      EM_SHARC           = 133    # Analog Devices SHARC family of 32-bit DSP processors
      EM_ECOG2           = 134    # Cyan Technology eCOG2 microprocessor
      EM_SCORE7          = 135    # Sunplus S+core7 RISC processor
      EM_DSP24           = 136    # New Japan Radio (NJR) 24-bit DSP Processor
      EM_VIDEOCORE3      = 137    # Broadcom VideoCore III processor
      EM_LATTICEMICO32   = 138    # RISC processor for Lattice FPGA architecture
      EM_SE_C17          = 139    # Seiko Epson C17 family
      EM_TI_C6000        = 140    # The Texas Instruments TMS320C6000 DSP family
      EM_TI_C2000        = 141    # The Texas Instruments TMS320C2000 DSP family
      EM_TI_C5500        = 142    # The Texas Instruments TMS320C55x DSP family
      EM_TI_ARP32        = 143    # Texas Instruments Application Specific RISC Processor, 32bit fetch
      EM_TI_PRU          = 144    # Texas Instruments Programmable Realtime Unit
      EM_MMDSP_PLUS      = 160    # STMicroelectronics 64bit VLIW Data Signal Processor
      EM_CYPRESS_M8C     = 161    # Cypress M8C microprocessor
      EM_R32C            = 162    # Renesas R32C series microprocessors
      EM_TRIMEDIA        = 163    # NXP Semiconductors TriMedia architecture family
      EM_QDSP6           = 164    # QUALCOMM DSP6 Processor
      EM_8051            = 165    # Intel 8051 and variants
      EM_STXP7X          = 166    # STMicroelectronics STxP7x family
      EM_NDS32           = 167    # Andes Technology compact code size embedded RISC processor family
      EM_ECOG1           = 168    # Cyan Technology eCOG1X family
      EM_ECOG1X          = 168    # Cyan Technology eCOG1X family
      EM_MAXQ30          = 169    # Dallas Semiconductor MAXQ30 Core Micro-controllers
      EM_XIMO16          = 170    # New Japan Radio (NJR) 16-bit DSP Processor
      EM_MANIK           = 171    # M2000 Reconfigurable RISC Microprocessor
      EM_CRAYNV2         = 172    # Cray Inc. NV2 vector architecture
      EM_RX              = 173    # Renesas RX family
      EM_METAG           = 174    # Imagination Technologies Meta processor architecture
      EM_MCST_ELBRUS     = 175    # MCST Elbrus general purpose hardware architecture
      EM_ECOG16          = 176    # Cyan Technology eCOG16 family
      EM_CR16            = 177    # National Semiconductor CompactRISC 16-bit processor
      EM_ETPU            = 178    # Freescale Extended Time Processing Unit
      EM_SLE9X           = 179    # Infineon Technologies SLE9X core
      EM_L1OM            = 180    # Intel L1OM
      EM_K1OM            = 181    # Intel K1OM
      EM_AARCH64         = 183    # ARM 64 bit
      EM_AVR32           = 185    # Atmel Corporation 32-bit microprocessor family
      EM_STM8            = 186    # STMicroeletronics STM8 8-bit microcontroller
      EM_TILE64          = 187    # Tilera TILE64 multicore architecture family
      EM_TILEPRO         = 188    # Tilera TILEPro
      EM_MICROBLAZE      = 189    # Xilinx MicroBlaze
      EM_CUDA            = 190    # NVIDIA CUDA architecture
      EM_TILEGX          = 191    # Tilera TILE-Gx
      EM_CLOUDSHIELD     = 192    # CloudShield architecture family
      EM_COREA_1ST       = 193    # KIPO-KAIST Core-A 1st generation processor family
      EM_COREA_2ND       = 194    # KIPO-KAIST Core-A 2nd generation processor family
      EM_ARC_COMPACT2    = 195    # Synopsys ARCompact V2
      EM_OPEN8           = 196    # Open8 8-bit RISC soft processor core
      EM_RL78            = 197    # Renesas RL78 family
      EM_VIDEOCORE5      = 198    # Broadcom VideoCore V processor
      EM_78K0R           = 199    # Renesas 78K0R
      EM_56800EX         = 200    # Freescale 56800EX Digital Signal Controller (DSC)
      EM_BA1             = 201    # Beyond BA1 CPU architecture
      EM_BA2             = 202    # Beyond BA2 CPU architecture
      EM_XCORE           = 203    # XMOS xCORE processor family
      EM_MCHP_PIC        = 204    # Microchip 8-bit PIC(r) family
      EM_INTELGT         = 205    # Intel Graphics Technology
      EM_KM32            = 210    # KM211 KM32 32-bit processor
      EM_KMX32           = 211    # KM211 KMX32 32-bit processor
      EM_KMX16           = 212    # KM211 KMX16 16-bit processor
      EM_KMX8            = 213    # KM211 KMX8 8-bit processor
      EM_KVARC           = 214    # KM211 KVARC processor
      EM_CDP             = 215    # Paneve CDP architecture family
      EM_COGE            = 216    # Cognitive Smart Memory Processor
      EM_COOL            = 217    # Bluechip Systems CoolEngine
      EM_NORC            = 218    # Nanoradio Optimized RISC
      EM_CSR_KALIMBA     = 219    # CSR Kalimba architecture family
      EM_Z80             = 220    # Zilog Z80
      EM_VISIUM          = 221    # Controls and Data Services VISIUMcore processor
      EM_FT32            = 222    # FTDI Chip FT32 high performance 32-bit RISC architecture
      EM_MOXIE           = 223    # Moxie processor family
      EM_AMDGPU          = 224    # AMD GPU architecture
      EM_LANAI           = 244    # Lanai 32-bit processor
      EM_CEVA            = 245    # CEVA Processor Architecture Family
      EM_CEVA_X2         = 246    # CEVA X2 Processor Family
      EM_BPF             = 247    # Linux BPF - in-kernel virtual machine
      EM_GRAPHCORE_IPU   = 248    # Graphcore Intelligent Processing Unit
      EM_IMG1            = 249    # Imagination Technologies
      EM_NFP             = 250    # Netronome Flow Processor (NFP)
      EM_VE              = 251    # NEC Vector Engine
      EM_CSKY            = 252    # C-SKY processor family
      EM_ARC_COMPACT3_64 = 253    # Synopsys ARCv2.3 64-bit
      EM_MCS6502         = 254    # MOS Technology MCS 6502 processor
      EM_ARC_COMPACT3    = 255    # Synopsys ARCv2.3 32-bit
      EM_KVX             = 256    # Kalray VLIW core of the MPPA processor family
      EM_65816           = 257    # WDC 65816/65C816
      EM_LOONGARCH       = 258    # LoongArch
      EM_KF32            = 259    # ChipON KungFu32
      EM_U16_U8CORE      = 260    # LAPIS nX-U16/U8
      EM_TACHYUM         = 261    # Tachyum
      EM_56800EF         = 262    # NXP 56800EF Digital Signal Controller (DSC)

      EM_FRV             = 0x5441 # Fujitsu FR-V

      # This is an interim value that we will use until the committee comes up with a final number.
      EM_ALPHA           = 0x9026

      # Bogus old m32r magic number, used by old tools.
      EM_CYGNUS_M32R     = 0x9041
      # This is the old interim value for S/390 architecture
      EM_S390_OLD        = 0xA390
      # Also Panasonic/MEI MN10300, AM33
      EM_CYGNUS_MN10300  = 0xbeef

      # Return the architecture name according to +val+.
      # Used by {ELFTools::ELFFile#machine}.
      #
      # Only supports famous archs.
      # @param [Integer] val Value of +e_machine+.
      # @return [String]
      #   Name of architecture.
      # @example
      #   mapping(3)
      #   #=> 'Intel 80386'
      #   mapping(6)
      #   #=> 'Intel 80386'
      #   mapping(62)
      #   #=> 'Advanced Micro Devices X86-64'
      #   mapping(1337)
      #   #=> '<unknown>: 0x539'
      def self.mapping(val)
        case val
        when EM_NONE then 'None'
        when EM_386, EM_486 then 'Intel 80386'
        when EM_860 then 'Intel 80860'
        when EM_MIPS then 'MIPS R3000'
        when EM_PPC then 'PowerPC'
        when EM_PPC64 then 'PowerPC64'
        when EM_ARM then 'ARM'
        when EM_IA_64 then 'Intel IA-64'
        when EM_AARCH64 then 'AArch64'
        when EM_X86_64 then 'Advanced Micro Devices X86-64'
        else format('<unknown>: 0x%x', val)
        end
      end
    end
    include EM

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
  end
end
