# frozen_string_literal: true

require 'elftools/dynamic/hash_table'
require 'elftools/exceptions'
require 'elftools/sections/symbol'
require 'elftools/structs'

module ELFTools
  module Dynamic
    # The symbols a file is loaded by, which the tags point at.
    #
    # @note
    #   This module is included by {ELFTools::Dynamic} and reads through the
    #   methods there, so it cannot be included on its own.
    module Symbols
      # Get the +n+-th symbol.
      #
      # Symbols are lazy loaded.
      # @note
      #   We cannot do bound checking of +n+ here, because nothing records how
      #   many symbols there are. {#num_symbols} is a lower bound rather than a
      #   bound, so checking against it would hide symbols this method reads
      #   correctly.
      # @param [Integer] n The index.
      # @return [ELFTools::Sections::Symbol] The desired symbol.
      # @raise [ELFTools::ELFError]
      #   If +DT_SYMTAB+ is absent, or its address is not in any loadable segment.
      def symbol_at(n)
        return if n.negative?

        @symbol_at_map ||= {}
        @symbol_at_map[n] ||= Sections::Symbol.new(
          Structs::Fields.new(Structs::ELF_sym[header.elf_class], stream, sym_offset + (n * sym_entsize),
                              elf_class: header.elf_class, endian: endian),
          stream, symstr: string_table_reader, machine: @machine, version: -> { version_at(n) }
        )
      end

      # How many symbols the tags reach.
      #
      # A hash table that records the number outright is answered with, because
      # nothing a file records can reach further than the table it counts.
      #
      # Where the file records no such table, nothing records how large its
      # symbol table is. The loader never enumerates it: it looks a name up
      # through a hash table and jumps straight to an index, so where the table
      # ends is none of its business. Two things bound it instead, the hash
      # table that indexes the names a file exports and the relocations that
      # name a symbol by index, and the answer is how far the further of the two
      # reaches.
      #
      # That answer is a lower bound. A symbol that is neither indexed by the
      # hash table nor named by a relocation is invisible to both, and is
      # missing from the count. {#symbol_at} is exact for any index.
      # @return [Integer] The number.
      # @example
      #   elf.dynamic.num_symbols
      #   #=> 9
      def num_symbols
        @num_symbols ||= counted_num_symbols || bounded_num_symbols
      end

      # Iterate all symbols.
      #
      # Symbols are lazy loaded, so {#symbol_by_name} only creates the symbols
      # it has to look at.
      # @yieldparam [ELFTools::Sections::Symbol] symbol A symbol object.
      # @yieldreturn [void]
      # @return [Enumerator<ELFTools::Sections::Symbol>, Array<ELFTools::Sections::Symbol>]
      #   If block is not given, an enumerator will be returned.
      #   Otherwise, return array of symbols.
      def each_symbol(&block)
        return enum_for(:each_symbol) unless block_given?

        Array.new(num_symbols) { |i| symbol_at(i).tap(&block) }
      end

      # The name this used to go by, kept so that it keeps working.
      alias each_symbols each_symbol

      # The symbols the tags point at, which is where a file that has been
      # stripped of its sections still records them.
      #
      # As many of them as {#num_symbols} reaches.
      # @return [Array<ELFTools::Sections::Symbol>] The symbols.
      # @example
      #   elf.dynamic.symbols.map(&:name)
      #   #=> ['', 'puts', '__stack_chk_fail', 'printf', '__libc_start_main']
      def symbols
        each_symbol.to_a
      end

      # Get symbol by its name.
      #
      # The hash tables answer first, which is the lookup the loader itself
      # performs and takes no scanning. Where one of them is built over every
      # symbol its answer is the whole answer, and a name it does not lead to
      # is not one the file records. Otherwise the name is searched for among
      # the symbols {#symbols} reaches, because a table need only index the
      # names a file exports and a file need not record one at all.
      # @param [String] name The name of symbol.
      # @return [ELFTools::Sections::Symbol, nil] The desired symbol.
      # @example
      #   elf.dynamic.symbol_by_name('__libc_start_main').type_name
      #   #=> 'STT_FUNC'
      def symbol_by_name(name)
        # Lazily, so that a table is only read when the ones before it have
        # not led anywhere.
        index = hash_tables.lazy.filter_map { |table| table.index_of(name) { |i| symbol_at(i).name == name } }.first
        return symbol_at(index) if index
        # A symbol with no name is the one thing such a table leaves out,
        # having nothing to be indexed by, so it is still searched for.
        return if !name.empty? && hash_tables.any?(&:covers_every_symbol?)

        each_symbol.find { |symbol| symbol.name == name }
      end

      private

      # The tables the file records the names it exports in, of whichever kinds
      # it records.
      # @return [Array<ELFTools::Dynamic::HashTable>] The tables.
      def hash_tables
        @hash_tables ||= { hash: HashTable::SysV, gnu_hash: HashTable::Gnu }.filter_map do |type, klass|
          tag = tag_by_type(type)
          klass.new(stream, offset_of(tag), elf_class: header.elf_class, endian:) if tag
        end
      end

      # How many symbols a table that counts them says there are.
      # @return [Integer, nil] The number, +nil+ if the file records no such table.
      def counted_num_symbols
        hash_tables.find(&:covers_every_symbol?)&.num_symbols
      end

      # How far what the file records reaches, for a file that counts its
      # symbols nowhere. Reading the relocations is what costs, so it is only
      # done for such a file.
      # @return [Integer] The number, zero if nothing reaches a symbol.
      def bounded_num_symbols
        (hash_tables.map(&:num_symbols) + [count_from_relocations]).compact.max || 0
      end

      # How far the relocations reach, i.e. the highest index they name plus one.
      # They only ever name the symbols something in the file refers to.
      # @return [Integer, nil] The number, +nil+ if none names a symbol.
      def count_from_relocations
        highest = relocations.map(&:symbol_index).max
        highest && highest + 1
      end

      # How many bytes an entry of the symbol table takes, which is what its
      # structure takes, which is also what +DT_SYMENT+ records and what a file
      # has no way of disagreeing with.
      # @return [Integer] The number.
      def sym_entsize
        @sym_entsize ||= Structs::ELF_sym[header.elf_class].num_bytes(elf_class: header.elf_class, endian: endian)
      end

      # What reads the table these symbols are named in, kept so that reading
      # a table of them does not make one for every symbol.
      # @return [Method] The method.
      def string_table_reader
        @string_table_reader ||= method(:string_table)
      end

      # Get the +DT_SYMTAB+'s +d_val+ offset related to file.
      # @return [Integer] The file offset.
      # @raise [ELFTools::ELFError]
      #   If +DT_SYMTAB+ is absent, or its address is not in any loadable segment.
      def sym_offset
        @sym_offset ||= begin
          symtab = tag_by_type(:symtab)
          raise ELFError, 'DT_SYMTAB not found' if symtab.nil?

          offset_of(symtab)
        end
      end
    end
  end
end
