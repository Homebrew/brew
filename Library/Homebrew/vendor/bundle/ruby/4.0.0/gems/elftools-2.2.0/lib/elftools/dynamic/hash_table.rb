# frozen_string_literal: true

require 'elftools/structs'

module ELFTools
  module Dynamic
    # A table of names the loader looks a symbol up in, instead of searching
    # the symbol table for it.
    #
    # A file records one of two kinds, or both of them. Both answer the same
    # two questions, how far the symbol table they index reaches and which
    # index a name sits at, and differ in how they are laid out, in how they
    # hash a name, and in which symbols they index at all.
    class HashTable
      # Instantiate a {ELFTools::Dynamic::HashTable} object.
      # @param [#pos=, #read] stream Streaming object.
      # @param [Integer] offset The file offset the table starts at.
      # @param [Integer] elf_class 32 or 64, the width of a mask of the table.
      # @param [Symbol] endian +:little+ or +:big+.
      def initialize(stream, offset, elf_class:, endian:)
        @stream = stream
        @offset = offset
        @elf_class = elf_class
        @endian = endian
      end

      # Whether the table is built over every symbol rather than over a subset
      # of them.
      #
      # Two things follow where it is. How many symbols it is built over is how
      # many there are, rather than how far it reaches. And a name it does not
      # lead to is not one the file records, so nothing is left to search.
      # @return [Boolean] The answer.
      def covers_every_symbol?
        false
      end

      private

      # The header the table starts with.
      # @return [ELFTools::Structs::ELFStruct] The header.
      def header
        @header ||= begin
          @stream.pos = @offset
          self.class::HEADER.new(endian: @endian).read(@stream)
        end
      end

      # Reads the four-byte word at an offset into the table, the unit buckets
      # and chains are laid out in.
      # @param [Integer] offset The offset into the table.
      # @return [Integer] The word.
      def word_at(offset)
        read_at(offset, 4)
      end

      # Reads an unsigned integer at an offset into the table.
      # @param [Integer] offset The offset into the table.
      # @param [Integer] bytes How many bytes it takes, 4 or 8.
      # @return [Integer] The integer.
      def read_at(offset, bytes)
        @stream.pos = @offset + offset
        @stream.read(bytes).unpack1("#{bytes == 4 ? 'L' : 'Q'}#{@endian == :big ? '>' : '<'}")
      end

      # The table +DT_HASH+ points at, which the System V ABI defines.
      #
      # A chain of it belongs to every symbol, so it is the one table that
      # records how many there are.
      class SysV < HashTable
        # The header the table starts with.
        HEADER = Structs::ELF_Hash

        # How many symbols the table is built over, which it records outright.
        # @return [Integer] The number.
        def num_symbols
          header.nchain.to_i
        end

        # (see ELFTools::Dynamic::HashTable#covers_every_symbol?)
        def covers_every_symbol?
          true
        end

        # The index a name sits at.
        #
        # A bucket leads to a chain of the indices whose names hash alike, so
        # the block is what tells them apart.
        # @param [String] name The name.
        # @yieldparam [Integer] index An index whose name hashes like +name+.
        # @yieldreturn [Boolean] Whether the symbol there is the one wanted.
        # @return [Integer, nil]
        #   The index, +nil+ if the table does not lead to the name.
        def index_of(name)
          return if header.nbucket.to_i.zero?

          n = word_at(buckets + ((hash_of(name) % header.nbucket.to_i) * 4))
          # Index zero is the undefined symbol, so it ends a chain instead of
          # belonging to one.
          while n.positive? && n < num_symbols
            return n if yield(n)

            n = word_at(chain + (n * 4))
          end
        end

        private

        # Where the buckets start, as an offset into the table.
        # @return [Integer] The offset.
        def buckets
          header.num_bytes
        end

        # Where the chains start, as an offset into the table.
        # @return [Integer] The offset.
        def chain
          buckets + (header.nbucket.to_i * 4)
        end

        # The hash the System V ABI defines, which keeps a name in 28 bits.
        # @param [String] name The name.
        # @return [Integer] The hash.
        def hash_of(name)
          name.each_byte.reduce(0) do |h, c|
            h = (h << 4) + c
            top = h & 0xf000_0000
            (h ^ (top >> 24)) & ~top
          end
        end
      end

      # The table +DT_GNU_HASH+ points at.
      #
      # It only indexes the defined symbols a file exports under a name, and
      # the symbols before {#symndx} are by construction not among them, so a
      # name it does not lead to may still be in the symbol table.
      class Gnu < HashTable
        # The header the table starts with.
        HEADER = Structs::ELF_GnuHash

        # How far the table reaches, i.e. the highest index it indexes plus one.
        # @return [Integer] The number.
        def num_symbols
          last = Array.new(header.nbuckets.to_i) { |i| word_at(buckets + (i * 4)) }.max || 0
          return symndx if last < symndx

          n = last - symndx
          n += 1 while word_at(chain + (n * 4)).even?
          symndx + n + 1
        end

        # The index a name sits at.
        #
        # A bucket leads to a chain of the indices whose names hash alike, so
        # the block is what tells them apart.
        # @param [String] name The name.
        # @yieldparam [Integer] index An index whose name hashes like +name+.
        # @yieldreturn [Boolean] Whether the symbol there is the one wanted.
        # @return [Integer, nil]
        #   The index, +nil+ if the table does not lead to the name.
        def index_of(name, &block)
          return if header.nbuckets.to_i.zero? || header.maskwords.to_i.zero?

          h = hash_of(name)
          return unless may_index?(h)

          n = word_at(buckets + ((h % header.nbuckets.to_i) * 4))
          return if n.zero? || n < symndx

          walk(n, h, &block)
        end

        private

        # The first symbol index the table indexes.
        # @return [Integer] The index.
        def symndx
          header.symndx.to_i
        end

        # Where the buckets start, as an offset into the table.
        # @return [Integer] The offset.
        def buckets
          header.num_bytes + (header.maskwords.to_i * @elf_class / 8)
        end

        # Where the chains start, as an offset into the table.
        # @return [Integer] The offset.
        def chain
          buckets + (header.nbuckets.to_i * 4)
        end

        # Walks the chain a bucket leads to, whose entries are the hashes of
        # the names it holds, with the lowest bit marking the last of them.
        # @param [Integer] index The index the bucket leads to.
        # @param [Integer] hash The hash of the name wanted.
        # @return [Integer, nil] The index, +nil+ if the chain ends without it.
        def walk(index, hash)
          loop do
            # The lowest bit belongs to the chain rather than to the hash.
            value = word_at(chain + ((index - symndx) * 4))
            return index if (value | 1) == (hash | 1) && yield(index)
            break if value.odd?

            index += 1
          end
        end

        # Whether the filter in front of the table rules a hash out, which it
        # answers for a name the file does not export without the table being
        # read at all. Looking a name up across a chain of files is what it is
        # there for.
        # @param [Integer] hash The hash.
        # @return [Boolean] Whether the name may be indexed.
        def may_index?(hash)
          width = @elf_class / 8
          word = read_at(header.num_bytes + (((hash / @elf_class) % header.maskwords.to_i) * width), width)
          mask = (1 << (hash % @elf_class)) | (1 << ((hash >> header.shift2.to_i) % @elf_class))
          word & mask == mask
        end

        # The hash GNU defines, which is djb2.
        # @param [String] name The name.
        # @return [Integer] The hash.
        def hash_of(name)
          name.each_byte.reduce(5381) { |h, c| ((h * 33) + c) & 0xffff_ffff }
        end
      end
    end
  end
end
