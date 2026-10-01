# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/dynamic/string_table'
require 'elftools/dynamic/symbols'
require 'elftools/dynamic/versions'
require 'elftools/dynamic/tag'
require 'elftools/exceptions'
require 'elftools/relative_relocations'
require 'elftools/relocation'
require 'elftools/structs'

module ELFTools
  # Define common methods for dynamic sections and dynamic segments.
  #
  # @note
  #   This module can only be included by {ELFTools::Sections::DynamicSection}
  #   and {ELFTools::Segments::DynamicSegment} because methods here assume some
  #   attributes exist.
  module Dynamic
    include Symbols
    include Versions

    # Iterate all tags.
    #
    # @note
    #   This method assume the following methods already exist:
    #     header
    #     tag_start
    # @yieldparam [ELFTools::Dynamic::Tag] tag
    # @return [Enumerator<ELFTools::Dynamic::Tag>, Array<ELFTools::Dynamic::Tag>]
    #   If block is not given, an enumerator will be returned.
    #   Otherwise, return array of tags.
    def each_tag(&block)
      return enum_for(:each_tag) unless block_given?

      arr = []
      0.step do |i|
        tag = tag_at(i).tap(&block)
        arr << tag
        break if tag.type == ELFTools::Constants::DT_NULL
      end
      arr
    end

    # The name this used to go by, kept so that it keeps working.
    alias each_tags each_tag

    # Use {#tags} to get all tags.
    # @return [Array<ELFTools::Dynamic::Tag>]
    #   Array of tags.
    def tags
      @tags ||= each_tag.to_a
    end

    # Get a tag of specific type.
    # @param [Integer, Symbol, String] type
    #   Constant value, symbol, or string of type
    #   is acceptable. See examples for more information.
    # @return [ELFTools::Dynamic::Tag] The desired tag.
    # @example
    #   dynamic = elf.segment_by_type(:dynamic)
    #   # type as integer
    #   dynamic.tag_by_type(0) # the null tag
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type(ELFTools::Constants::DT_NULL)
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #
    #   # symbol
    #   dynamic.tag_by_type(:null)
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type(:pltgot)
    #   #=> #<ELFTools::Dynamic::Tag:0x0055d3d2d91b28 @header={:d_tag=>3, :d_val=>6295552}>
    #
    #   # string
    #   dynamic.tag_by_type('null')
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type('DT_PLTGOT')
    #   #=> #<ELFTools::Dynamic::Tag:0x0055d3d2d91b28 @header={:d_tag=>3, :d_val=>6295552}>
    def tag_by_type(type)
      type = Util.to_constant(Constants::DT, type)
      each_tag.find { |tag| tag.type == type }
    end

    # Get tags of specific type.
    # @param [Integer, Symbol, String] type
    #   Constant value, symbol, or string of type
    #   is acceptable. See examples for more information.
    # @return [Array<ELFTools::Dynamic::Tag>] The desired tags.
    #
    # @see #tag_by_type
    def tags_by_type(type)
      type = Util.to_constant(Constants::DT, type)
      each_tag.select { |tag| tag.type == type }
    end

    # Get the +n+-th tag.
    #
    # Tags are lazy loaded.
    # @note
    #   This method assume the following methods already exist:
    #     header
    #     tag_start
    # @note
    #   We cannot do bound checking of +n+ here since the only way to get size
    #   of tags is calling +tags.size+.
    # @param [Integer] n The index.
    # @return [ELFTools::Dynamic::Tag] The desired tag.
    def tag_at(n)
      return if n.negative?

      @tag_at_map ||= {}
      return @tag_at_map[n] if @tag_at_map[n]

      elf_class = header.elf_class
      offset = tag_start + (n * Structs::ELF_Dyn.num_bytes(elf_class: elf_class, endian: endian))
      fields = Structs::Fields.new(Structs::ELF_Dyn, stream, offset, elf_class: elf_class, endian: endian)
      @tag_at_map[n] = Tag.new(fields, stream, string_table)
    end

    # The relocations the tags point at.
    #
    # Three tables record them: the one +DT_REL+ or +DT_RELA+ names, the one
    # +DT_JMPREL+ names, whose entries are of the kind +DT_PLTREL+ names, and
    # the one +DT_RELR+ names, which packs the relocations that only add the
    # load bias into a bitmap and so records no type of its own.
    # @return [Array<ELFTools::Relocation>] The relocations, in the order the
    #   tags record them, the packed ones last.
    # @raise [ELFTools::ELFError]
    #   If a table is not in any loadable segment.
    # @example
    #   elf.dynamic.relocations.map(&:type_name).uniq
    #   #=> ['R_X86_64_GLOB_DAT', 'R_X86_64_JUMP_SLOT']
    def relocations
      @relocations ||= relocation_tables.flat_map { |start, size, rela| read_relocations(start, size, rela) } +
                       packed_relocations
    end

    private

    def endian
      header.class.self_endian
    end

    # Where each table of relocations starts, the tag recording how many bytes
    # it takes, and whether its entries record an addend.
    # @return [Array<Array(ELFTools::Dynamic::Tag, ELFTools::Dynamic::Tag, Boolean)>] The tables.
    def relocation_tables
      tables = %i[rel rela].filter_map do |type|
        tag = tag_by_type(type)
        [tag, tag_by_type(:"#{type}sz"), type == :rela] if tag
      end
      jmprel = tag_by_type(:jmprel)
      return tables if jmprel.nil?

      tables << [jmprel, tag_by_type(:pltrelsz), tag_by_type(:pltrel).header.d_val.to_i == Constants::DT_RELA]
    end

    # Reads the table +DT_RELR+ names, which is absent from most files.
    # @return [Array<ELFTools::Relocation>] The relocations, empty without it.
    def packed_relocations
      start = tag_by_type(:relr)
      return [] if start.nil?

      offset = offset_of(start)
      RelativeRelocations.new(stream, offset...(offset + tag_by_type(:relrsz).header.d_val.to_i),
                              elf_class: header.elf_class, endian:, machine: @machine).to_a
    end

    # Reads one table of relocations.
    # @return [Array<ELFTools::Relocation>] The relocations.
    def read_relocations(start, size, rela)
      klass = rela ? Structs::ELF_Rela : Structs::ELF_Rel
      offset = offset_of(start)
      # An entry takes what its structure takes. DT_RELAENT and DT_RELENT
      # record the same number, which a file has no way of disagreeing with
      # and every file here agrees with.
      elf_class = header.elf_class
      entsize = klass.num_bytes(elf_class: elf_class, endian: endian)
      Array.new(size.header.d_val.to_i / entsize) do |i|
        fields = Structs::Fields.new(klass, stream, offset + (i * entsize), elf_class: elf_class, endian: endian)
        Relocation.new(fields, stream, machine: @machine)
      end
    end

    # The file offset the address a tag records points at.
    # @param [ELFTools::Dynamic::Tag] tag The tag.
    # @return [Integer] The file offset.
    # @raise [ELFTools::ELFError]
    #   If the address is not in any loadable segment.
    def offset_of(tag)
      vma = tag.header.d_val.to_i
      @offset_from_vma.call(vma) ||
        raise(ELFError, format('Invalid %s address 0x%x', Constants::DT.mapping(@machine, tag.type), vma))
    end

    # The names the tags and the symbols point at.
    # @return [ELFTools::Dynamic::StringTable] The string table.
    def string_table
      @string_table ||= StringTable.new(stream, method(:str_offset))
    end

    # Get the DT_STRTAB's +d_val+ offset related to file.
    # @return [Integer] The file offset.
    # @raise [ELFTools::ELFError]
    #   If DT_STRTAB is absent, or its address is not in any loadable segment.
    def str_offset
      @str_offset ||= begin
        strtab = tag_by_type(:strtab)
        raise ELFError, 'DT_STRTAB not found' if strtab.nil?

        offset_of(strtab)
      end
    end
  end
end
