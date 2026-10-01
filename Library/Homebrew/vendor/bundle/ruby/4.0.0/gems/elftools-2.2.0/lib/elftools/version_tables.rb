# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/structs'

module ELFTools
  # The two tables a file records its versions in.
  #
  # One holds the versions the file needs of the files it is loaded with, the
  # other the versions it defines for what it exports, and a symbol names one
  # of either by the same index. Both are chains, each entry saying how far
  # off the next one is, and both are recorded twice over: the tags point at
  # them, and so do sections.
  class VersionTables
    # The name each index of either table names.
    # @param [Array<ELFTools::VersionTables::Requirement>] requirements The requirements.
    # @param [Array<ELFTools::VersionTables::Definition>] definitions The definitions.
    # @return [Hash{Integer => String}] The names.
    def self.names(requirements, definitions)
      (requirements.flat_map(&:versions) + definitions).to_h { |version| [version.index, version.name] }
    end

    # The version a symbol records, read against the names of the tables.
    # @param [Integer, nil] recorded
    #   What the symbol records, which is an index with the highest bit marking
    #   a version asked for by name rather than the default one.
    # @param [Hash{Integer => String}] names What {names} answered.
    # @return [ELFTools::VersionTables::Version, nil]
    #   The version, +nil+ where the symbol names none: a symbol of the file
    #   itself, a symbol of no version at all, and a name nothing records.
    def self.version(recorded, names)
      return if recorded.nil?

      index = recorded & ~Constants::VER_NDX_HIDDEN
      return if index <= Constants::VER_NDX_GLOBAL

      name = names[index]
      Version.new(name, index, hidden: !(recorded & Constants::VER_NDX_HIDDEN).zero?) if name
    end

    # Instantiate a {ELFTools::VersionTables} object.
    # @param [#pos=, #read] stream Streaming object.
    # @param [#name_at] strtab The table the names are recorded in.
    # @param [Symbol] endian +:little+ or +:big+.
    def initialize(stream, strtab, endian:)
      @stream = stream
      @strtab = strtab
      @endian = endian
    end

    # Reads the versions a file needs of the files it is loaded with.
    # @param [Integer] at The file offset the table starts at.
    # @param [Integer] count How many entries it has.
    # @return [Array<ELFTools::VersionTables::Requirement>] The requirements.
    def requirements(at, count)
      chain(at, count, Structs::ELF_Verneed, :vn_next) do |need, from|
        versions = chain(from + need.vn_aux.to_i, need.vn_cnt.to_i, Structs::ELF_Vernaux, :vna_next) do |aux, _|
          Version.new(@strtab.name_at(aux.vna_name.to_i), aux.vna_other.to_i)
        end
        Requirement.new(@strtab.name_at(need.vn_file.to_i), versions)
      end
    end

    # Reads the versions a file defines for what it exports.
    # @param [Integer] at The file offset the table starts at.
    # @param [Integer] count How many entries it has.
    # @return [Array<ELFTools::VersionTables::Definition>] The definitions.
    def definitions(at, count)
      chain(at, count, Structs::ELF_Verdef, :vd_next) do |defn, from|
        names = chain(from + defn.vd_aux.to_i, defn.vd_cnt.to_i, Structs::ELF_Verdaux, :vda_next) do |aux, _|
          @strtab.name_at(aux.vda_name.to_i)
        end
        # The first name is the version's own, the rest are what it descends from.
        Definition.new(names.first, defn.vd_ndx.to_i, names.drop(1),
                       base: !(defn.vd_flags.to_i & Constants::VER_FLG_BASE).zero?)
      end
    end

    private

    # Reads a chain of entries, each saying how far off the one after it is.
    # @return [Array] What the block makes of each entry.
    def chain(at, count, klass, following)
      Array.new(count) do
        entry = klass.new(endian: @endian, offset: at)
        @stream.pos = at
        entry.read(@stream)
        yield(entry, at).tap { at += entry.send(following).to_i }
      end
    end

    # A version a file needs or defines.
    class Version
      attr_reader :name # @return [String] The name, +GLIBC_2.2.5+ for instance.
      attr_reader :index # @return [Integer] The index the symbols name it with.

      # Instantiate a {ELFTools::VersionTables::Version} object.
      # @param [String] name The name.
      # @param [Integer] index The index.
      # @param [Boolean] hidden Whether a symbol binds to it as a version that is not the default.
      def initialize(name, index, hidden: false)
        @name = name
        @index = index
        @hidden = hidden
      end

      # Whether the symbol binding to this version binds to something other
      # than the default, which is what more than one version of a name means.
      # @return [Boolean] The answer.
      def hidden?
        @hidden
      end
    end

    # The versions a file needs of one of the files it is loaded with.
    class Requirement
      attr_reader :file # @return [String] The name of the file, +libc.so.6+ for instance.
      attr_reader :versions # @return [Array<ELFTools::VersionTables::Version>] The versions needed of it.

      # Instantiate a {ELFTools::VersionTables::Requirement} object.
      # @param [String] file The name of the file.
      # @param [Array<ELFTools::VersionTables::Version>] versions The versions.
      def initialize(file, versions)
        @file = file
        @versions = versions
      end
    end

    # A version a file defines for what it exports.
    class Definition
      attr_reader :name # @return [String] The name.
      attr_reader :index # @return [Integer] The index the symbols name it with.
      attr_reader :parents # @return [Array<String>] The names of the versions it descends from.

      # Instantiate a {ELFTools::VersionTables::Definition} object.
      # @param [String] name The name.
      # @param [Integer] index The index.
      # @param [Array<String>] parents The names it descends from.
      # @param [Boolean] base Whether it names the file rather than a version of it.
      def initialize(name, index, parents, base: false)
        @name = name
        @index = index
        @parents = parents
        @base = base
      end

      # Whether this names the file itself rather than a version of it, which
      # the first definition of a file does.
      # @return [Boolean] The answer.
      def base?
        @base
      end
    end
  end
end
