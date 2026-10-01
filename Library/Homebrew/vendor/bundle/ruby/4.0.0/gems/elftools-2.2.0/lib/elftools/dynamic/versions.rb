# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/version_tables'

module ELFTools
  module Dynamic
    # The versions a file binds its symbols to.
    #
    # Two tables record them, the versions the file needs of the files it is
    # loaded with and the versions it defines for what it exports, and a symbol
    # names one of either by the same index.
    #
    # @note
    #   This module is included by {ELFTools::Dynamic} and reads through the
    #   methods there, so it cannot be included on its own.
    module Versions
      # The versions this file needs of the files it is loaded with.
      # @return [Array<ELFTools::VersionTables::Requirement>]
      #   The requirements, in the order the table records them.
      # @example
      #   elf.dynamic.version_requirements.map { |need| [need.file, need.versions.map(&:name)] }
      #   #=> [['libc.so.6', ['GLIBC_2.4', 'GLIBC_2.2.5']]]
      def version_requirements
        @version_requirements ||= read_table(:verneed, :verneednum) { |at, count| tables.requirements(at, count) }
      end

      # The versions this file defines for what it exports.
      #
      # The first of them is the file itself rather than a version of it, which
      # {ELFTools::VersionTables::Definition#base?} tells apart.
      # @return [Array<ELFTools::VersionTables::Definition>]
      #   The definitions, in the order the table records them.
      # @example
      #   elf.dynamic.version_definitions.map(&:name).first(3)
      #   #=> ['libc.so.6', 'GLIBC_2.2.5', 'GLIBC_2.2.6']
      def version_definitions
        @version_definitions ||= read_table(:verdef, :verdefnum) { |at, count| tables.definitions(at, count) }
      end

      private

      # The version the +n+-th symbol binds to.
      # @param [Integer] n The symbol index.
      # @return [ELFTools::VersionTables::Version, nil]
      #   The version, +nil+ if the file records none, or if the symbol is one
      #   of the file's own or of no version at all.
      def version_at(n)
        VersionTables.version(versym_at(n), versions_by_index)
      end

      # What the +n+-th symbol records as its version.
      # @return [Integer, nil] The index, +nil+ if the file records none.
      def versym_at(n)
        @versym_offset ||= begin
          tag = tag_by_type(:versym)
          tag && offset_of(tag)
        end
        return if @versym_offset.nil?

        stream.pos = @versym_offset + (n * 2)
        stream.read(2).to_s.unpack1(endian == :big ? 'S>' : 'S<')
      end

      # The tables the tags point at.
      # @return [ELFTools::VersionTables] The tables.
      def tables
        @tables ||= VersionTables.new(stream, string_table, endian:)
      end

      # Reads a table the tags point at, as many entries as a tag counts.
      # @return [Array] What the block makes of it, empty without the tags.
      def read_table(address, count)
        tag = tag_by_type(address)
        return [] if tag.nil?

        yield(offset_of(tag), tag_by_type(count).header.d_val.to_i)
      end

      # The name each index names, of either table.
      # @return [Hash{Integer => String}] The names.
      def versions_by_index
        @versions_by_index ||= VersionTables.names(version_requirements, version_definitions)
      end
    end
  end
end
