# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/relocation'
require 'elftools/structs'

module ELFTools
  # The relocations a file packs into a bitmap instead of recording one by one.
  #
  # Almost every relocation of a file that is loaded anywhere only adds the
  # load bias to a word, which takes an entry recording an address, a type that
  # is the same every time, and an addend that repeats what the word already
  # holds. A file may pack them instead, as a run of addresses in ascending
  # order, and spend a bit rather than an entry on each.
  #
  # An even entry is an address, and relocates the word there. An odd entry is
  # a bitmap of the words following the last address, a set bit relocating one
  # of them. Nothing records a type, because every relocation here is the one
  # {ELFTools::Constants::R.relative} names.
  class RelativeRelocations
    # Instantiate a {ELFTools::RelativeRelocations} object.
    # @param [#pos=, #read] stream Streaming object.
    # @param [Range<Integer>] bytes The file offsets the table occupies.
    # @param [Integer] elf_class 32 or 64, the width of an entry.
    # @param [Symbol] endian +:little+ or +:big+.
    # @param [Integer] machine
    #   The machine of the file, which decides what these relocations are of.
    def initialize(stream, bytes, elf_class:, endian:, machine:)
      @stream = stream
      @bytes = bytes
      @elf_class = elf_class
      @endian = endian
      @machine = machine
    end

    # The relocations the table packs.
    # @return [Array<ELFTools::Relocation>]
    #   The relocations, in the ascending order the table records them.
    def to_a
      type = Constants::R.relative(@machine)
      addresses.map do |address, from|
        fields = Structs::Fields.from(Structs::ELF_Rel, { r_offset: address, r_info: 0 },
                                      elf_class: @elf_class, endian: @endian, offset: from)
        relocation = Relocation.new(fields, @stream, machine: @machine)
        # Through the relocation, so that the type is laid out in +r_info+ the
        # way the machine lays it out.
        relocation.type = type if type
        relocation
      end
    end

    private

    # How many bytes an entry takes, which is the width of an address.
    # @return [Integer] The number.
    def width
      @elf_class / 8
    end

    # Every address the table relocates, and the entry it was read from.
    # @return [Array<Array(Integer, Integer)>] The addresses.
    def addresses
      found = []
      # Where a bitmap counts from, which an address moves to just past itself.
      here = 0
      entries.each do |entry, from|
        if entry.even?
          found << [entry, from]
          here = entry + width
        else
          # The lowest bit says the entry is a bitmap rather than an address.
          (1...(width * 8)).each { |bit| found << [here + ((bit - 1) * width), from] if entry[bit] == 1 }
          here += ((width * 8) - 1) * width
        end
      end
      found
    end

    # What the table records, and where each was read from.
    # @return [Array<Array(Integer, Integer)>] The entries.
    def entries
      @stream.pos = @bytes.begin
      format = "#{width == 8 ? 'Q' : 'L'}#{@endian == :big ? '>' : '<'}"
      @stream.read(@bytes.size).to_s.unpack("#{format}*").each_with_index.map { |e, i| [e, @bytes.begin + (i * width)] }
    end
  end
end
