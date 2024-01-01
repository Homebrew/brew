# frozen_string_literal: true

module MachO
  # Classes and constants for parsing the headers of Mach-O binaries.
  module Headers
    # big-endian fat magic
    # @api private
    FAT_MAGIC = 0xcafebabe

    # little-endian fat magic
    # @note This is defined for completeness, but should never appear in ruby-macho code,
    #  since fat headers are always big-endian.
    # @api private
    FAT_CIGAM = 0xbebafeca

    # 64-bit big-endian fat magic
    FAT_MAGIC_64 = 0xcafebabf

    # 64-bit little-endian fat magic
    # @note This is defined for completeness, but should never appear in ruby-macho code,
    #   since fat headers are always big-endian.
    FAT_CIGAM_64 = 0xbfbafeca

    # 32-bit big-endian magic
    # @api private
    MH_MAGIC = 0xfeedface

    # 32-bit little-endian magic
    # @api private
    MH_CIGAM = 0xcefaedfe

    # 64-bit big-endian magic
    # @api private
    MH_MAGIC_64 = 0xfeedfacf

    # 64-bit little-endian magic
    # @api private
    MH_CIGAM_64 = 0xcffaedfe

    # compressed mach-o magic
    # @api private
    COMPRESSED_MAGIC = 0x636f6d70 # "comp"

    # a compressed mach-o slice, using LZSS for compression
    # @api private
    COMP_TYPE_LZSS = 0x6c7a7373 # "lzss"

    # a compressed mach-o slice, using LZVN ("FastLib") for compression
    # @api private
    COMP_TYPE_FASTLIB = 0x6c7a766e # "lzvn"

    # association of magic numbers to string representations
    # @api private
    MH_MAGICS = {
      FAT_MAGIC => "FAT_MAGIC",
      FAT_MAGIC_64 => "FAT_MAGIC_64",
      MH_MAGIC => "MH_MAGIC",
      MH_CIGAM => "MH_CIGAM",
      MH_MAGIC_64 => "MH_MAGIC_64",
      MH_CIGAM_64 => "MH_CIGAM_64",
    }.freeze

    # mask for CPUs with 64-bit architectures (when running a 64-bit ABI?)
    # @api private
    CPU_ARCH_ABI64 = 0x01000000

    # mask for CPUs with 64-bit architectures (when running a 32-bit ABI?)
    # @see https://github.com/Homebrew/ruby-macho/issues/113
    # @api private
    CPU_ARCH_ABI32 = 0x02000000

    # any CPU (unused?)
    # @api private
    CPU_TYPE_ANY = -1

    # m68k compatible CPUs
    # @api private
    CPU_TYPE_MC680X0 = 0x06

    # i386 and later compatible CPUs
    # @api private
    CPU_TYPE_I386 = 0x07

    # x86_64 (AMD64) compatible CPUs
    # @api private
    CPU_TYPE_X86_64 = (CPU_TYPE_I386 | CPU_ARCH_ABI64)

    # 32-bit ARM compatible CPUs
    # @api private
    CPU_TYPE_ARM = 0x0c

    # m88k compatible CPUs
    # @api private
    CPU_TYPE_MC88000 = 0xd

    # 64-bit ARM compatible CPUs
    # @api private
    CPU_TYPE_ARM64 = (CPU_TYPE_ARM | CPU_ARCH_ABI64)

    # 64-bit ARM compatible CPUs (running in 32-bit mode?)
    # @see https://github.com/Homebrew/ruby-macho/issues/113
    CPU_TYPE_ARM64_32 = (CPU_TYPE_ARM | CPU_ARCH_ABI32)

    # PowerPC compatible CPUs
    # @api private
    CPU_TYPE_POWERPC = 0x12

    # PowerPC64 compatible CPUs
    # @api private
    CPU_TYPE_POWERPC64 = (CPU_TYPE_POWERPC | CPU_ARCH_ABI64)

    # association of cpu types to symbol representations
    # @api private
    CPU_TYPES = {
      CPU_TYPE_ANY => :any,
      CPU_TYPE_I386 => :i386,
      CPU_TYPE_X86_64 => :x86_64,
      CPU_TYPE_ARM => :arm,
      CPU_TYPE_ARM64 => :arm64,
      CPU_TYPE_ARM64_32 => :arm64_32,
      CPU_TYPE_POWERPC => :ppc,
      CPU_TYPE_POWERPC64 => :ppc64,
    }.freeze

    # mask for CPU subtype capabilities
    # @api private
    CPU_SUBTYPE_MASK = 0xff000000

    # 64-bit libraries (undocumented!)
    # @see http://llvm.org/docs/doxygen/html/Support_2MachO_8h_source.html
    # @api private
    CPU_SUBTYPE_LIB64 = 0x80000000

    # the lowest common sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_I386 = 3

    # the i486 sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_486 = 4

    # the i486SX sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_486SX = 132

    # the i586 (P5, Pentium) sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_586 = 5

    # @see CPU_SUBTYPE_586
    # @api private
    CPU_SUBTYPE_PENT = CPU_SUBTYPE_586

    # the Pentium Pro (P6) sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_PENTPRO = 22

    # the Pentium II (P6, M3?) sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_PENTII_M3 = 54

    # the Pentium II (P6, M5?) sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_PENTII_M5 = 86

    # the Pentium 4 (Netburst) sub-type for `CPU_TYPE_I386`
    # @api private
    CPU_SUBTYPE_PENTIUM_4 = 10

    # the lowest common sub-type for `CPU_TYPE_MC680X0`
    # @api private
    CPU_SUBTYPE_MC680X0_ALL = 1

    # @see CPU_SUBTYPE_MC680X0_ALL
    # @api private
    CPU_SUBTYPE_MC68030 = CPU_SUBTYPE_MC680X0_ALL

    # the 040 subtype for `CPU_TYPE_MC680X0`
    # @api private
    CPU_SUBTYPE_MC68040 = 2

    # the 030 subtype for `CPU_TYPE_MC680X0`
    # @api private
    CPU_SUBTYPE_MC68030_ONLY = 3

    # the lowest common sub-type for `CPU_TYPE_X86_64`
    # @api private
    CPU_SUBTYPE_X86_64_ALL = CPU_SUBTYPE_I386

    # the Haskell sub-type for `CPU_TYPE_X86_64`
    # @api private
    CPU_SUBTYPE_X86_64_H = 8

    # the lowest common sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_ALL = 0

    # the v4t sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V4T = 5

    # the v6 sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V6 = 6

    # the v5 sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V5TEJ = 7

    # the xscale (v5 family) sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_XSCALE = 8

    # the v7 sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7 = 9

    # the v7f (Cortex A9) sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7F = 10

    # the v7s ("Swift") sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7S = 11

    # the v7k ("Kirkwood40") sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7K = 12

    # the v6m sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V6M = 14

    # the v7m sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7M = 15

    # the v7em sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V7EM = 16

    # the v8 sub-type for `CPU_TYPE_ARM`
    # @api private
    CPU_SUBTYPE_ARM_V8 = 13

    # the lowest common sub-type for `CPU_TYPE_ARM64`
    # @api private
    CPU_SUBTYPE_ARM64_ALL = 0

    # the v8 sub-type for `CPU_TYPE_ARM64`
    # @api private
    CPU_SUBTYPE_ARM64_V8 = 1

    # the v8 sub-type for `CPU_TYPE_ARM64_32`
    # @api private
    CPU_SUBTYPE_ARM64_32_V8 = 1

    # the e (A12) sub-type for `CPU_TYPE_ARM64`
    # @api private
    CPU_SUBTYPE_ARM64E = 2

    # the lowest common sub-type for `CPU_TYPE_MC88000`
    # @api private
    CPU_SUBTYPE_MC88000_ALL = 0

    # @see CPU_SUBTYPE_MC88000_ALL
    # @api private
    CPU_SUBTYPE_MMAX_JPC = CPU_SUBTYPE_MC88000_ALL

    # the 100 sub-type for `CPU_TYPE_MC88000`
    # @api private
    CPU_SUBTYPE_MC88100 = 1

    # the 110 sub-type for `CPU_TYPE_MC88000`
    # @api private
    CPU_SUBTYPE_MC88110 = 2

    # the lowest common sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_ALL = 0

    # the 601 sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_601 = 1

    # the 602 sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_602 = 2

    # the 603 sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_603 = 3

    # the 603e (G2) sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_603E = 4

    # the 603ev sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_603EV = 5

    # the 604 sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_604 = 6

    # the 604e sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_604E = 7

    # the 620 sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_620 = 8

    # the 750 (G3) sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_750 = 9

    # the 7400 (G4) sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_7400 = 10

    # the 7450 (G4 "Voyager") sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_7450 = 11

    # the 970 (G5) sub-type for `CPU_TYPE_POWERPC`
    # @api private
    CPU_SUBTYPE_POWERPC_970 = 100

    # any CPU sub-type for CPU type `CPU_TYPE_POWERPC64`
    # @api private
    CPU_SUBTYPE_POWERPC64_ALL = CPU_SUBTYPE_POWERPC_ALL

    # association of CPU types/subtype pairs to symbol representations in
    # (very) roughly descending order of commonness
    # @see https://opensource.apple.com/source/cctools/cctools-877.8/libstuff/arch.c
    # @api private
    CPU_SUBTYPES = {
      CPU_TYPE_I386 => {
        CPU_SUBTYPE_I386 => :i386,
        CPU_SUBTYPE_486 => :i486,
        CPU_SUBTYPE_486SX => :i486SX,
        CPU_SUBTYPE_586 => :i586, # also "pentium" in arch(3)
        CPU_SUBTYPE_PENTPRO => :i686, # also "pentpro" in arch(3)
        CPU_SUBTYPE_PENTII_M3 => :pentIIm3,
        CPU_SUBTYPE_PENTII_M5 => :pentIIm5,
        CPU_SUBTYPE_PENTIUM_4 => :pentium4,
      }.freeze,
      CPU_TYPE_X86_64 => {
        CPU_SUBTYPE_X86_64_ALL => :x86_64,
        CPU_SUBTYPE_X86_64_H => :x86_64h,
      }.freeze,
      CPU_TYPE_ARM => {
        CPU_SUBTYPE_ARM_ALL => :arm,
        CPU_SUBTYPE_ARM_V4T => :armv4t,
        CPU_SUBTYPE_ARM_V6 => :armv6,
        CPU_SUBTYPE_ARM_V5TEJ => :armv5,
        CPU_SUBTYPE_ARM_XSCALE => :xscale,
        CPU_SUBTYPE_ARM_V7 => :armv7,
        CPU_SUBTYPE_ARM_V7F => :armv7f,
        CPU_SUBTYPE_ARM_V7S => :armv7s,
        CPU_SUBTYPE_ARM_V7K => :armv7k,
        CPU_SUBTYPE_ARM_V6M => :armv6m,
        CPU_SUBTYPE_ARM_V7M => :armv7m,
        CPU_SUBTYPE_ARM_V7EM => :armv7em,
        CPU_SUBTYPE_ARM_V8 => :armv8,
      }.freeze,
      CPU_TYPE_ARM64 => {
        CPU_SUBTYPE_ARM64_ALL => :arm64,
        CPU_SUBTYPE_ARM64_V8 => :arm64v8,
        CPU_SUBTYPE_ARM64E => :arm64e,
      }.freeze,
      CPU_TYPE_ARM64_32 => {
        CPU_SUBTYPE_ARM64_32_V8 => :arm64_32v8,
      }.freeze,
      CPU_TYPE_POWERPC => {
        CPU_SUBTYPE_POWERPC_ALL => :ppc,
        CPU_SUBTYPE_POWERPC_601 => :ppc601,
        CPU_SUBTYPE_POWERPC_603 => :ppc603,
        CPU_SUBTYPE_POWERPC_603E => :ppc603e,
        CPU_SUBTYPE_POWERPC_603EV => :ppc603ev,
        CPU_SUBTYPE_POWERPC_604 => :ppc604,
        CPU_SUBTYPE_POWERPC_604E => :ppc604e,
        CPU_SUBTYPE_POWERPC_750 => :ppc750,
        CPU_SUBTYPE_POWERPC_7400 => :ppc7400,
        CPU_SUBTYPE_POWERPC_7450 => :ppc7450,
        CPU_SUBTYPE_POWERPC_970 => :ppc970,
      }.freeze,
      CPU_TYPE_POWERPC64 => {
        CPU_SUBTYPE_POWERPC64_ALL => :ppc64,
        # apparently the only exception to the naming scheme
        CPU_SUBTYPE_POWERPC_970 => :ppc970_64,
      }.freeze,
      CPU_TYPE_MC680X0 => {
        CPU_SUBTYPE_MC680X0_ALL => :m68k,
        CPU_SUBTYPE_MC68030 => :mc68030,
        CPU_SUBTYPE_MC68040 => :mc68040,
      },
      CPU_TYPE_MC88000 => {
        CPU_SUBTYPE_MC88000_ALL => :m88k,
      },
    }.freeze

    # relocatable object file
    # @api private
    MH_OBJECT = 0x1

    # demand paged executable file
    # @api private
    MH_EXECUTE = 0x2

    # fixed VM shared library file
    # @api private
    MH_FVMLIB = 0x3

    # core dump file
    # @api private
    MH_CORE = 0x4

    # preloaded executable file
    # @api private
    MH_PRELOAD = 0x5

    # dynamically bound shared library
    # @api private
    MH_DYLIB = 0x6

    # dynamic link editor
    # @api private
    MH_DYLINKER = 0x7

    # dynamically bound bundle file
    # @api private
    MH_BUNDLE = 0x8

    # shared library stub for static linking only, no section contents
    # @api private
    MH_DYLIB_STUB = 0x9

    # companion file with only debug sections
    # @api private
    MH_DSYM = 0xa

    # x86_64 kexts
    # @api private
    MH_KEXT_BUNDLE = 0xb

    # a set of Mach-Os, running in the same userspace, sharing a linkedit.  The kext collection files are an example
    # of this object type
    # @api private
    MH_FILESET = 0xc

    # association of filetypes to Symbol representations
    # @api private
    MH_FILETYPES = {
      MH_OBJECT => :object,
      MH_EXECUTE => :execute,
      MH_FVMLIB => :fvmlib,
      MH_CORE => :core,
      MH_PRELOAD => :preload,
      MH_DYLIB => :dylib,
      MH_DYLINKER => :dylinker,
      MH_BUNDLE => :bundle,
      MH_DYLIB_STUB => :dylib_stub,
      MH_DSYM => :dsym,
      MH_KEXT_BUNDLE => :kext_bundle,
      MH_FILESET => :fileset,
    }.freeze

    # association of mach header flag symbols to values
    # @api private
    MH_FLAGS = {
      :MH_NOUNDEFS => 0x1,
      :MH_INCRLINK => 0x2,
      :MH_DYLDLINK => 0x4,
      :MH_BINDATLOAD => 0x8,
      :MH_PREBOUND => 0x10,
      :MH_SPLIT_SEGS => 0x20,
      :MH_LAZY_INIT => 0x40,
      :MH_TWOLEVEL => 0x80,
      :MH_FORCE_FLAT => 0x100,
      :MH_NOMULTIDEFS => 0x200,
      :MH_NOPREFIXBINDING => 0x400,
      :MH_PREBINDABLE => 0x800,
      :MH_ALLMODSBOUND => 0x1000,
      :MH_SUBSECTIONS_VIA_SYMBOLS => 0x2000,
      :MH_CANONICAL => 0x4000,
      :MH_WEAK_DEFINES => 0x8000,
      :MH_BINDS_TO_WEAK => 0x10000,
      :MH_ALLOW_STACK_EXECUTION => 0x20000,
      :MH_ROOT_SAFE => 0x40000,
      :MH_SETUID_SAFE => 0x80000,
      :MH_NO_REEXPORTED_DYLIBS => 0x100000,
      :MH_PIE => 0x200000,
      :MH_DEAD_STRIPPABLE_DYLIB => 0x400000,
      :MH_HAS_TLV_DESCRIPTORS => 0x800000,
      :MH_NO_HEAP_EXECUTION => 0x1000000,
      :MH_APP_EXTENSION_SAFE => 0x02000000,
      :MH_NLIST_OUTOFSYNC_WITH_DYLDINFO => 0x04000000,
      :MH_SIM_SUPPORT => 0x08000000,
      :MH_DYLIB_IN_CACHE => 0x80000000,
    }.freeze

    # Fat binary header structure
    # @see MachO::FatArch
    class FatHeader < MachOStructure
      # @return [Integer] the magic number of the header (and file)
      field :magic, :uint32, :endian => :big

      # @return [Integer] the number of fat architecture structures following the header
      field :nfat_arch, :uint32, :endian => :big

      # @return [String] the serialized fields of the fat header
      def serialize
        [magic, nfat_arch].pack(self.class.format)
      end

      # @return [Hash] a hash representation of this {FatHeader}
      def to_h
        {
          "magic" => magic,
          "magic_sym" => MH_MAGICS[magic],
          "nfat_arch" => nfat_arch,
        }.merge super
      end
    end

    # 32-bit fat binary header architecture structure. A 32-bit fat Mach-O has one or more of
    #  these, indicating one or more internal Mach-O blobs.
    # @note "32-bit" indicates the fact that this structure stores 32-bit offsets, not that the
    #  Mach-Os that it points to necessarily *are* 32-bit.
    # @see MachO::Headers::FatHeader
    class FatArch < MachOStructure
      # @return [Integer] the CPU type of the Mach-O
      field :cputype, :uint32, :endian => :big

      # @return [Integer] the CPU subtype of the Mach-O
      field :cpusubtype, :uint32, :endian => :big, :mask => CPU_SUBTYPE_MASK

      # @return [Integer] the file offset to the beginning of the Mach-O data
      field :offset, :uint32, :endian => :big

      # @return [Integer] the size, in bytes, of the Mach-O data
      field :size, :uint32, :endian => :big

      # @return [Integer] the alignment, as a power of 2
      field :align, :uint32, :endian => :big

      # @return [String] the serialized fields of the fat arch
      def serialize
        [cputype, cpusubtype, offset, size, align].pack(self.class.format)
      end

      # @return [Hash] a hash representation of this {FatArch}
      def to_h
        {
          "cputype" => cputype,
          "cputype_sym" => CPU_TYPES[cputype],
          "cpusubtype" => cpusubtype,
          "cpusubtype_sym" => CPU_SUBTYPES[cputype][cpusubtype],
          "offset" => offset,
          "size" => size,
          "align" => align,
        }.merge super
      end
    end

    # 64-bit fat binary header architecture structure. A 64-bit fat Mach-O has one or more of
    #  these, indicating one or more internal Mach-O blobs.
    # @note "64-bit" indicates the fact that this structure stores 64-bit offsets, not that the
    #  Mach-Os that it points to necessarily *are* 64-bit.
    # @see MachO::Headers::FatHeader
    class FatArch64 < FatArch
      # @return [Integer] the file offset to the beginning of the Mach-O data
      field :offset, :uint64, :endian => :big

      # @return [Integer] the size, in bytes, of the Mach-O data
      field :size, :uint64, :endian => :big

      # @return [void]
      field :reserved, :uint32, :endian => :big, :default => 0

      # @return [String] the serialized fields of the fat arch
      def serialize
        [cputype, cpusubtype, offset, size, align, reserved].pack(self.class.format)
      end

      # @return [Hash] a hash representation of this {FatArch64}
      def to_h
        {
          "reserved" => reserved,
        }.merge super
      end
    end

    # 32-bit Mach-O file header structure
    class MachHeader < MachOStructure
      # @return [Integer] the magic number
      field :magic, :uint32

      # @return [Integer] the CPU type of the Mach-O
      field :cputype, :uint32

      # @return [Integer] the CPU subtype of the Mach-O
      field :cpusubtype, :uint32, :mask => CPU_SUBTYPE_MASK

      # @return [Integer] the file type of the Mach-O
      field :filetype, :uint32

      # @return [Integer] the number of load commands in the Mach-O
      field :ncmds, :uint32

      # @return [Integer] the size of all load commands, in bytes, in the Mach-O
      field :sizeofcmds, :uint32

      # @return [Integer] the header flags associated with the Mach-O
      field :flags, :uint32

      # @example
      #  puts "this mach-o has position-independent execution" if header.flag?(:MH_PIE)
      # @param flag [Symbol] a mach header flag symbol
      # @return [Boolean] true if `flag` is present in the header's flag section
      def flag?(flag)
        flag = MH_FLAGS[flag]

        return false if flag.nil?

        flags & flag == flag
      end

      # @return [Boolean] whether or not the file is of type `MH_OBJECT`
      def object?
        filetype == Headers::MH_OBJECT
      end

      # @return [Boolean] whether or not the file is of type `MH_EXECUTE`
      def executable?
        filetype == Headers::MH_EXECUTE
      end

      # @return [Boolean] whether or not the file is of type `MH_FVMLIB`
      def fvmlib?
        filetype == Headers::MH_FVMLIB
      end

      # @return [Boolean] whether or not the file is of type `MH_CORE`
      def core?
        filetype == Headers::MH_CORE
      end

      # @return [Boolean] whether or not the file is of type `MH_PRELOAD`
      def preload?
        filetype == Headers::MH_PRELOAD
      end

      # @return [Boolean] whether or not the file is of type `MH_DYLIB`
      def dylib?
        filetype == Headers::MH_DYLIB
      end

      # @return [Boolean] whether or not the file is of type `MH_DYLINKER`
      def dylinker?
        filetype == Headers::MH_DYLINKER
      end

      # @return [Boolean] whether or not the file is of type `MH_BUNDLE`
      def bundle?
        filetype == Headers::MH_BUNDLE
      end

      # @return [Boolean] whether or not the file is of type `MH_DSYM`
      def dsym?
        filetype == Headers::MH_DSYM
      end

      # @return [Boolean] whether or not the file is of type `MH_KEXT_BUNDLE`
      def kext?
        filetype == Headers::MH_KEXT_BUNDLE
      end

      # @return [Boolean] whether or not the file is of type `MH_FILESET`
      def fileset?
        filetype == Headers::MH_FILESET
      end

      # @return [Boolean] true if the Mach-O has 32-bit magic, false otherwise
      def magic32?
        Utils.magic32?(magic)
      end

      # @return [Boolean] true if the Mach-O has 64-bit magic, false otherwise
      def magic64?
        Utils.magic64?(magic)
      end

      # @return [Integer] the file's internal alignment
      def alignment
        magic32? ? 4 : 8
      end

      # @return [Hash] a hash representation of this {MachHeader}
      def to_h
        {
          "magic" => magic,
          "magic_sym" => MH_MAGICS[magic],
          "cputype" => cputype,
          "cputype_sym" => CPU_TYPES[cputype],
          "cpusubtype" => cpusubtype,
          "cpusubtype_sym" => CPU_SUBTYPES[cputype][cpusubtype],
          "filetype" => filetype,
          "filetype_sym" => MH_FILETYPES[filetype],
          "ncmds" => ncmds,
          "sizeofcmds" => sizeofcmds,
          "flags" => flags,
          "alignment" => alignment,
        }.merge super
      end
    end

    # 64-bit Mach-O file header structure
    class MachHeader64 < MachHeader
      # @return [void]
      field :reserved, :uint32

      # @return [Hash] a hash representation of this {MachHeader64}
      def to_h
        {
          "reserved" => reserved,
        }.merge super
      end
    end

    # Prelinked kernel/"kernelcache" header structure
    class PrelinkedKernelHeader < MachOStructure
      # @return [Integer] the magic number for a compressed header ({COMPRESSED_MAGIC})
      field :signature, :uint32, :endian => :big

      # @return [Integer] the type of compression used
      field :compress_type, :uint32, :endian => :big

      # @return [Integer] a checksum for the uncompressed data
      field :adler32, :uint32, :endian => :big

      # @return [Integer] the size of the uncompressed data, in bytes
      field :uncompressed_size, :uint32, :endian => :big

      # @return [Integer] the size of the compressed data, in bytes
      field :compressed_size, :uint32, :endian => :big

      # @return [Integer] the version of the prelink format
      field :prelink_version, :uint32, :endian => :big

      # @return [void]
      field :reserved, :string, :size => 40, :unpack => "L>10"

      # @return [void]
      field :platform_name, :string, :size => 64

      # @return [void]
      field :root_path, :string, :size => 256

      # @return [Boolean] whether this prelinked kernel supports KASLR
      def kaslr?
        prelink_version >= 1
      end

      # @return [Boolean] whether this prelinked kernel is compressed with LZSS
      def lzss?
        compress_type == COMP_TYPE_LZSS
      end

      # @return [Boolean] whether this prelinked kernel is compressed with LZVN
      def lzvn?
        compress_type == COMP_TYPE_FASTLIB
      end

      # @return [Hash] a hash representation of this {PrelinkedKernelHeader}
      def to_h
        {
          "signature" => signature,
          "compress_type" => compress_type,
          "adler32" => adler32,
          "uncompressed_size" => uncompressed_size,
          "compressed_size" => compressed_size,
          "prelink_version" => prelink_version,
          "reserved" => reserved,
          "platform_name" => platform_name,
          "root_path" => root_path,
        }.merge super
      end
    end
  end
end
