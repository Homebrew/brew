# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/relocation'
require 'elftools/sections/section'
require 'elftools/structs'

module ELFTools
  module Sections
    # Class of relocation section.
    # Usually for sections .rel.* and .rela.*,
    # which record relocations in ELF file.
    class RelocationSection < Section
      # Instantiate a {RelocationSection} object.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   See {Section#initialize} for more information.
      # @param [#pos=, #read] stream
      #   See {Section#initialize} for more information.
      # @param [Integer] machine
      #   The machine of the ELF file, which decides what a relocation type
      #   means. This should be +e_machine+ of the ELF header.
      def initialize(header, stream, machine: nil, **_kwargs)
        @machine = machine
        super
      end

      # Is this relocation a RELA or REL type.
      # @return [Boolean] If is RELA.
      def rela?
        header.sh_type == Constants::SHT_RELA
      end

      # Number of relocations in this section.
      # @return [Integer] The number.
      def num_relocations
        header.sh_size / header.sh_entsize
      end

      # Acquire the +n+-th relocation, 0-based.
      #
      # relocations are lazy loaded.
      # @param [Integer] n The index.
      # @return [ELFTools::Relocation, nil]
      #   The target relocation.
      #   If +n+ is out of bound, +nil+ is returned.
      def relocation_at(n)
        @relocations ||= LazyArray.new(num_relocations, &method(:create_relocation))
        @relocations[n]
      end

      # Iterate all relocations.
      #
      # All relocations are lazy loading, the relocation
      # only be created whenever accessing it.
      # @yieldparam [ELFTools::Relocation] rel A relocation object.
      # @yieldreturn [void]
      # @return [Enumerator<ELFTools::Relocation>, Array<ELFTools::Relocation>]
      #   If block is not given, an enumerator will be returned.
      #   Otherwise, the whole relocations will be returned.
      def each_relocation(&block)
        return enum_for(:each_relocation) unless block_given?

        Array.new(num_relocations) do |i|
          relocation_at(i).tap(&block)
        end
      end

      # The name this used to go by, kept so that it keeps working.
      alias each_relocations each_relocation

      # Simply use {#relocations} to get all relocations.
      # @return [Array<ELFTools::Relocation>]
      #   Whole relocations.
      def relocations
        each_relocation.to_a
      end

      private

      def create_relocation(n)
        klass = rela? ? Structs::ELF_Rela : Structs::ELF_Rel
        fields = Structs::Fields.new(klass, stream, table_offset + (n * entsize),
                                     elf_class: header.elf_class, endian: header.class.self_endian)
        Relocation.new(fields, stream, machine: @machine)
      end

      # Where this table starts in the file, asked of the header once rather
      # than once for every relocation read.
      # @return [Integer] The file offset.
      def table_offset
        @table_offset ||= header.sh_offset.to_i
      end

      # How many bytes this table spaces its entries by.
      # @return [Integer] The number.
      def entsize
        @entsize ||= header.sh_entsize.to_i
      end
    end
  end
end
