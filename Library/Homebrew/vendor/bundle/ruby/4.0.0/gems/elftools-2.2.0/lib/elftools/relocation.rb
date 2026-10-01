# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/structs'
require 'elftools/util'

module ELFTools
  # A relocation entry.
  #
  # Can be either a REL or RELA relocation.
  class Relocation
    attr_reader :stream # @return [#pos=, #read] Streaming object.

    # Instantiate a {Relocation} object.
    # @param [ELFTools::Structs::ELF_Rel, ELFTools::Structs::ELF_Rela, ELFTools::Structs::Fields] header
    #   The relocation header, or what the file records in one.
    #   {ELFTools::Structs::Fields} answers what the relocation records until
    #   something asks for {#header} itself, which builds the structure then.
    # @param [#pos=, #read] stream The streaming object.
    # @param [Integer] machine
    #   The machine of the ELF file, which decides what {#type} means and how
    #   {#header} records it.
    def initialize(header, stream, machine: nil)
      @fields = header.is_a?(Structs::Fields) ? header : Structs::Fields.of(header)
      @stream = stream
      @machine = machine
    end

    # The structure the file records this relocation in.
    #
    # One is built here for a relocation read without it, which is what
    # assigning to a field of one needs and what {ELFTools::ELFFile#patches}
    # reports the changes of.
    # @return [ELFTools::Structs::ELF_Rel, ELFTools::Structs::ELF_Rela] The structure.
    def header
      @fields.struct
    end

    # Which symbol this relocation is against, as an index into the symbol
    # table.
    # @return [Integer] The symbol index.
    def symbol_index
      sym_and_type.first
    end

    # What this relocation does, which only means something together with the
    # machine of the file. {#type_name} names it.
    # @return [Integer] The relocation type.
    def type
      sym_and_type.last
    end

    # Sets which symbol this relocation is against.
    # @param [Integer] index The symbol index.
    # @raise [ArgumentError] If the bits recording it cannot hold it.
    # @example
    #   relocation.symbol_index = 3
    def symbol_index=(index)
      @fields[:r_info] = info_of(Util.fits!(index, index_bits, 'Symbol index'), type)
    end

    # Sets what this relocation does.
    # @param [Integer] type The relocation type.
    # @raise [ArgumentError] If the bits recording it cannot hold it.
    # @example
    #   relocation.type = ELFTools::Constants::R::X86_64::R_X86_64_JUMP_SLOT
    def type=(type)
      @fields[:r_info] = info_of(symbol_index, Util.fits!(type, type_bits, 'Relocation type'))
    end

    # The name of {#type}.
    #
    # Every architecture numbers relocation types on its own, so the name is
    # only known when the machine of the file is.
    # @return [String] The name.
    # @example
    #   relocation.type_name
    #   #=> 'R_X86_64_JUMP_SLOT'
    def type_name
      Constants::R.mapping(@machine, type)
    end

    private

    # The +r_info+ recording a symbol index and a type, laid out the way this
    # file lays it out. The inverse of {#sym_and_type}.
    # @return [Integer] The +r_info+.
    def info_of(index, type)
      return mips64_info_of(index, type) if mips64?

      (index << mask_bit) | type
    end

    # The +r_info+ as the 64-bit MIPS ABI records it, leaving the bytes the
    # ABI keeps for itself as they were.
    # @return [Integer] The +r_info+.
    def mips64_info_of(index, type)
      info = @fields[:r_info]
      return (index << 32) | (info & 0xffff_ff00) | type if @fields.endian == :big

      (info & 0x00ff_ffff_0000_0000) | (type << 56) | index
    end

    # How many bits record a symbol index.
    # @return [Integer] The number.
    def index_bits
      mips64? ? 32 : (@fields.elf_class - mask_bit)
    end

    # How many bits record a relocation type.
    # @return [Integer] The number.
    def type_bits
      mips64? ? 8 : mask_bit
    end

    # What +r_info+ records, i.e. a symbol index and a relocation type. Most
    # machines split the field in half between the two, one lays it out its
    # own way.
    # @return [Array(Integer, Integer)] The symbol index and the type.
    def sym_and_type
      return mips64_sym_and_type if mips64?

      info = @fields[:r_info]
      [info >> mask_bit, info & ((1 << mask_bit) - 1)]
    end

    # Whether the file records relocations the way the 64-bit MIPS ABI does,
    # which is the one layout that departs from halving +r_info+.
    # @return [Boolean] The answer.
    def mips64?
      @machine == Constants::EM_MIPS && @fields.elf_class == 64
    end

    # Reads +r_info+ as the 64-bit MIPS ABI records it, i.e. a symbol index of
    # four bytes followed by four bytes the ABI keeps for itself, the last of
    # which is the type reported here. Those bytes are ordered as the rest of
    # the file is, which is why the two ends of the field swap places.
    # @example
    #   # A big endian file records the symbol index first,
    #   #   00 00 00 08 | 00    05     18     07
    #   #   sym         | ssym  type3  type2  type
    #   0x0000000800051807 #=> [8, 7]
    #   # a little endian one records the very same relocation as
    #   0x0718050000000008 #=> [8, 7]
    # @return [Array(Integer, Integer)] The symbol index and the type.
    def mips64_sym_and_type
      info = @fields[:r_info]
      return [info >> 32, info & 0xff] if @fields.endian == :big

      [info & 0xffff_ffff, info >> 56]
    end

    def mask_bit
      @fields.elf_class == 32 ? 8 : 32
    end
  end
end
