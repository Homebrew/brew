# frozen_string_literal: true

require 'elftools/sections/section'
require 'elftools/sections/symbol'
require 'elftools/structs'
require 'elftools/version_tables'

module ELFTools
  module Sections
    # Class of symbol table section.
    # Usually for section .symtab and .dynsym,
    # which will refer to symbols in ELF file.
    class SymTabSection < Section
      # Instantiate a {SymTabSection} object.
      # There's a +section_at+ lambda for {SymTabSection}
      # to easily fetch other sections.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   See {Section#initialize} for more information.
      # @param [#pos=, #read] stream
      #   See {Section#initialize} for more information.
      # @param [Proc] sections
      #   The method for fetching the sections, which is where the names and
      #   the versions of these symbols are recorded. This lambda should be
      #   {ELFTools::ELFFile#sections}.
      # @param [Integer] machine
      #   The machine of the ELF file, which decides what the fields of a
      #   symbol mean. This should be +e_machine+ of the ELF header.
      def initialize(header, stream, sections: nil, machine: nil, **_kwargs)
        @sections = sections
        @machine = machine
        # For faster #symbol_by_name
        super
      end

      # Number of symbols.
      # @return [Integer] The number.
      # @example
      #   symtab.num_symbols
      #   #=> 75
      def num_symbols
        header.sh_size / header.sh_entsize
      end

      # Acquire the +n+-th symbol, 0-based.
      #
      # Symbols are lazy loaded.
      # @param [Integer] n The index.
      # @return [ELFTools::Sections::Symbol, nil]
      #   The target symbol.
      #   If +n+ is out of bound, +nil+ is returned.
      def symbol_at(n)
        @symbols ||= LazyArray.new(num_symbols, &method(:create_symbol))
        @symbols[n]
      end

      # Iterate all symbols.
      #
      # All symbols are lazy loading, the symbol
      # only be created whenever accessing it.
      # This method is useful for {#symbol_by_name}
      # since not all symbols need to be created.
      # @yieldparam [ELFTools::Sections::Symbol] sym A symbol object.
      # @yieldreturn [void]
      # @return [Enumerator<ELFTools::Sections::Symbol>, Array<ELFTools::Sections::Symbol>]
      #   If block is not given, an enumerator will be returned.
      #   Otherwise return array of symbols.
      def each_symbol(&block)
        return enum_for(:each_symbol) unless block_given?

        Array.new(num_symbols) do |i|
          symbol_at(i).tap(&block)
        end
      end

      # The name this used to go by, kept so that it keeps working.
      alias each_symbols each_symbol

      # Simply use {#symbols} to get all symbols.
      # @return [Array<ELFTools::Sections::Symbol>]
      #   The whole symbols.
      def symbols
        each_symbol.to_a
      end

      # Get symbol by its name.
      # @param [String] name
      #   The name of symbol.
      # @return [ELFTools::Sections::Symbol] Desired symbol.
      def symbol_by_name(name)
        each_symbol.find { |symbol| symbol.name == name }
      end

      # Return the symbol string section.
      # Lazy loaded.
      # @return [ELFTools::Sections::StrTabSection] The string table section.
      def symstr
        @symstr ||= @sections.call[header.sh_link]
      end

      private

      def create_symbol(n)
        Symbol.new(
          Structs::Fields.new(Structs::ELF_sym[header.elf_class], stream, table_offset + (n * entsize),
                              elf_class: header.elf_class, endian: header.class.self_endian),
          stream, symstr: symstr_reader, machine: @machine, version: -> { version_at(n) }
        )
      end

      # Where this table starts in the file, asked of the header once rather
      # than once for every symbol read.
      # @return [Integer] The file offset.
      def table_offset
        @table_offset ||= header.sh_offset.to_i
      end

      # How many bytes this table spaces its entries by.
      # @return [Integer] The number.
      def entsize
        @entsize ||= header.sh_entsize.to_i
      end

      # What reads the section these symbols are named in, kept so that
      # reading the table does not make one for every symbol.
      # @return [Method] The method.
      def symstr_reader
        @symstr_reader ||= method(:symstr)
      end

      # The version the +n+-th symbol binds to.
      # @return [ELFTools::VersionTables::Version, nil]
      #   The version, +nil+ unless this is the table a file is loaded by and
      #   the file records versions at all.
      def version_at(n)
        return if versions.nil?

        VersionTables.version(versions.version_at(n), versions_by_index)
      end

      # The section recording which version each of these symbols binds to,
      # which is the one naming this table.
      # @return [ELFTools::Sections::VersionSection, nil] The section.
      def versions
        return @versions if defined?(@versions)

        @versions = @sections&.call&.find do |sec|
          sec.is_a?(VersionSection) && @sections.call[sec.header.sh_link].equal?(self)
        end
      end

      # The name each index the symbols record names.
      # @return [Hash{Integer => String}] The names.
      def versions_by_index
        @versions_by_index ||= VersionTables.names(
          @sections.call.grep(VersionNeedSection).flat_map(&:requirements),
          @sections.call.grep(VersionDefinitionSection).flat_map(&:definitions)
        )
      end
    end
  end
end
