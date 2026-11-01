# typed: strict
# frozen_string_literal: true

require "os/linux/ld"

# {Pathname} extension for dealing with ELF files.
# @see https://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_header
module ELFShim
  extend T::Helpers

  MAGIC_NUMBER_OFFSET = 0
  private_constant :MAGIC_NUMBER_OFFSET
  MAGIC_NUMBER_ASCII = "\x7fELF"
  private_constant :MAGIC_NUMBER_ASCII

  OS_ABI_OFFSET = 0x07
  private_constant :OS_ABI_OFFSET
  OS_ABI_SYSTEM_V = 0
  private_constant :OS_ABI_SYSTEM_V
  OS_ABI_LINUX = 3
  private_constant :OS_ABI_LINUX

  TYPE_OFFSET = 0x10
  private_constant :TYPE_OFFSET
  TYPE_EXECUTABLE = 2
  private_constant :TYPE_EXECUTABLE
  TYPE_SHARED = 3
  private_constant :TYPE_SHARED

  ARCHITECTURE_OFFSET = 0x12
  private_constant :ARCHITECTURE_OFFSET
  ARCHITECTURE_I386 = 0x3
  private_constant :ARCHITECTURE_I386
  ARCHITECTURE_POWERPC = 0x14
  private_constant :ARCHITECTURE_POWERPC
  ARCHITECTURE_POWERPC64 = 0x15
  private_constant :ARCHITECTURE_POWERPC64
  ARCHITECTURE_ARM = 0x28
  private_constant :ARCHITECTURE_ARM
  ARCHITECTURE_X86_64 = 0x3E
  private_constant :ARCHITECTURE_X86_64
  ARCHITECTURE_AARCH64 = 0xB7
  private_constant :ARCHITECTURE_AARCH64

  requires_ancestor { Pathname }

  sig { params(path: T.anything).void }
  def initialize(path)
    @elf = T.let(nil, T.nilable(T::Boolean))
    @arch = T.let(nil, T.nilable(Symbol))
    @elf_type = T.let(nil, T.nilable(Symbol))
    @rpath = T.let(nil, T.nilable(String))
    @interpreter = T.let(nil, T.nilable(String))
    @dynamic_elf = T.let(nil, T.nilable(T::Boolean))
    @metadata = T.let(nil, T.nilable(Metadata))
    @section_names = T.let(nil, T.nilable(T::Array[String]))

    super
  end

  sig { params(offset: Integer).returns(Integer) }
  def read_uint8(offset)
    read(1, offset).unpack1("C")
  end

  sig { params(offset: Integer).returns(Integer) }
  def read_uint16(offset)
    read(2, offset).unpack1("v")
  end

  sig { returns(T::Boolean) }
  def elf?
    return @elf unless @elf.nil?

    return @elf = false if read(MAGIC_NUMBER_ASCII.size, MAGIC_NUMBER_OFFSET) != MAGIC_NUMBER_ASCII

    # Check that this ELF file is for Linux or System V.
    # OS_ABI is often set to 0 (System V), regardless of the target platform.
    @elf = [OS_ABI_LINUX, OS_ABI_SYSTEM_V].include? read_uint8(OS_ABI_OFFSET)
  end

  sig { returns(Symbol) }
  def arch
    return :dunno unless elf?

    @arch ||= case read_uint16(ARCHITECTURE_OFFSET)
    when ARCHITECTURE_I386 then :i386
    when ARCHITECTURE_X86_64 then :x86_64
    when ARCHITECTURE_POWERPC then :ppc32
    when ARCHITECTURE_POWERPC64 then :ppc64
    when ARCHITECTURE_ARM then :arm
    when ARCHITECTURE_AARCH64 then :arm64
    else :dunno
    end
  end

  sig { params(wanted_arch: Symbol).returns(T::Boolean) }
  def arch_compatible?(wanted_arch)
    return true unless elf?

    # Treat ppc64le and ppc64 the same
    wanted_arch = :ppc64 if wanted_arch == :ppc64le

    wanted_arch == arch
  end

  sig { returns(Symbol) }
  def elf_type
    return :dunno unless elf?

    @elf_type ||= case read_uint16(TYPE_OFFSET)
    when TYPE_EXECUTABLE then :executable
    when TYPE_SHARED then :dylib
    else :dunno
    end
  end

  sig { returns(T::Boolean) }
  def dylib?
    elf_type == :dylib
  end

  sig { returns(T::Boolean) }
  def binary_executable?
    elf_type == :executable
  end

  # The runtime search path, such as:
  # "/lib:/usr/lib:/usr/local/lib"
  sig { returns(T.nilable(String)) }
  def rpath
    metadata.rpath
  end

  # An array of runtime search path entries, such as:
  # ["/lib", "/usr/lib", "/usr/local/lib"]
  sig { returns(T::Array[String]) }
  def rpaths
    Array(rpath&.split(":"))
  end

  sig { returns(T.nilable(String)) }
  def interpreter
    metadata.interpreter
  end

  sig { returns(T::Boolean) }
  def pie?
    metadata.pie?
  end

  sig { params(interpreter: T.nilable(String), rpath: T.nilable(String)).void }
  def patch!(interpreter: nil, rpath: nil)
    return if interpreter.blank? && rpath.blank?

    save_using_patchelf_rb interpreter, rpath
  end

  sig { returns(T::Boolean) }
  def dynamic_elf?
    metadata.dynamic_elf?
  end

  # Only bottling needs these and reading every section header costs far more
  # than the rest of {Metadata}, so read them separately on demand.
  sig { returns(T::Array[String]) }
  def section_names
    @section_names ||= begin
      require "elftools"
      open("rb") { |file| ELFTools::ELFFile.new(file).sections.map(&:name).compact_blank }
    end
  end

  # Where each library was found, by the expanded RPATH searched, whether the
  # file ignores the default library paths and the library's name.
  LibraryLookups = T.type_alias { T::Hash[[T.nilable(T::Array[String]), T::Boolean, String], ::Pathname] }
  @library_lookups = T.let(nil, T.nilable(LibraryLookups))

  sig { returns(T.nilable(LibraryLookups)) }
  def self.library_lookups = @library_lookups

  # Looks each library up only once while the block runs. Only use it where
  # nothing installs or removes libraries, such as while checking a keg.
  sig { params(_block: T.proc.void).void }
  def self.caching_library_lookups(&_block)
    outer_lookups = @library_lookups
    @library_lookups ||= {}
    yield
  ensure
    @library_lookups = outer_lookups
  end

  # Helper class for reading metadata from an ELF file.
  class Metadata
    # Values from the ELF specification for the fields {#read_directly} reads.
    # @see https://refspecs.linuxfoundation.org/elf/gabi4+/contents.html
    IDENT_BYTESIZE = 16
    CLASS_OFFSET = 4
    DATA_OFFSET = 5
    ELFCLASS32 = 1
    ELFCLASS64 = 2
    ELFDATA2LSB = 1
    ELFDATA2MSB = 2
    ELF32_HEADER_BYTESIZE = 52
    ELF64_HEADER_BYTESIZE = 64
    ELF32_PROGRAM_HEADER_BYTESIZE = 32
    ELF64_PROGRAM_HEADER_BYTESIZE = 56
    PN_XNUM = 0xffff
    PT_LOAD = 1
    PT_DYNAMIC = 2
    PT_INTERP = 3
    DT_NULL = 0
    DT_NEEDED = 1
    DT_STRTAB = 5
    DT_SONAME = 14
    DT_RPATH = 15
    DT_RUNPATH = 29
    DT_FLAGS_1 = 0x6ffffffb
    DF_1_NODEFLIB = 0x800
    DF_1_PIE = 0x08000000
    private_constant :IDENT_BYTESIZE, :CLASS_OFFSET, :DATA_OFFSET, :ELFCLASS32, :ELFCLASS64, :ELFDATA2LSB,
                     :ELFDATA2MSB, :ELF32_HEADER_BYTESIZE, :ELF64_HEADER_BYTESIZE, :ELF32_PROGRAM_HEADER_BYTESIZE,
                     :ELF64_PROGRAM_HEADER_BYTESIZE, :PN_XNUM, :PT_LOAD, :PT_DYNAMIC, :PT_INTERP, :DT_NULL,
                     :DT_NEEDED, :DT_STRTAB, :DT_SONAME, :DT_RPATH, :DT_RUNPATH, :DT_FLAGS_1, :DF_1_NODEFLIB,
                     :DF_1_PIE

    # Everything {Metadata} reads from a file. {#read_directly} and
    # {#read_using_patchelf_rb} each return all of it or nothing, so when the
    # first gives up part of the way through, nothing it read is kept.
    class Fields < T::Struct
      const :dynamic_elf, T::Boolean
      const :dylib_id, T.nilable(String)
      const :needed, T::Array[String]
      const :interpreter, T.nilable(String)
      const :rpath, T.nilable(String)
      const :dt_flags_1, T.nilable(Integer)
    end
    private_constant :Fields

    sig { returns(ELFShim) }
    attr_reader :path

    sig { returns(T.nilable(String)) }
    attr_reader :dylib_id

    sig { returns(T::Boolean) }
    def dynamic_elf?
      @dynamic_elf
    end

    sig { returns(T.nilable(String)) }
    attr_reader :interpreter

    sig { returns(T.nilable(String)) }
    attr_reader :rpath

    sig { params(path: ELFShim).void }
    def initialize(path)
      @path = path
      @dylibs = T.let(nil, T.nilable(T::Array[String]))

      fields = path.open("rb") { |file| read_directly(file) } || read_using_patchelf_rb
      @dynamic_elf = T.let(fields.dynamic_elf, T::Boolean)
      @dylib_id = T.let(fields.dylib_id, T.nilable(String))
      @needed = T.let(fields.needed, T::Array[String])
      @interpreter = T.let(fields.interpreter, T.nilable(String))
      @rpath = T.let(fields.rpath, T.nilable(String))
      @dt_flags_1 = T.let(fields.dt_flags_1, T.nilable(Integer))
    end

    sig { returns(T::Boolean) }
    def pie?
      return false if @dt_flags_1.nil?

      @dt_flags_1.anybits?(DF_1_PIE)
    end

    sig { returns(T::Array[String]) }
    def dylibs
      @dylibs ||= @needed.map { |lib| cached_full_lib_path(lib).to_s }
    end

    private

    # A keg's files mostly share an RPATH and need the same few libraries, so
    # inside {ELFShim.caching_library_lookups} each search is made once. The key
    # is everything {#find_full_lib_path} depends on besides the loader's paths
    # and the files on disk, neither of which changes while that runs.
    sig { params(basename: String).returns(::Pathname) }
    def cached_full_lib_path(basename)
      lookups = ELFShim.library_lookups
      return find_full_lib_path(basename) if lookups.nil?

      search_paths = rpath&.split(":")&.map do |local_path|
        OS::Linux::Elf.expand_elf_dst(local_path, "ORIGIN", path.parent)
      end
      nodeflib = @dt_flags_1.to_i.anybits?(DF_1_NODEFLIB)
      lookups[[search_paths, nodeflib, basename]] ||= find_full_lib_path(basename)
    end

    # Reads the fields straight from the program headers and the dynamic section,
    # which is far faster than parsing every header with elftools. Returns nil
    # for anything unusual, such as a truncated file, to leave it to patchelf.rb.
    sig { params(file: File).returns(T.nilable(Fields)) }
    def read_directly(file)
      ident = read_bytes(file, 0, IDENT_BYTESIZE)
      return unless ident.start_with?(MAGIC_NUMBER_ASCII)
      return unless [ELFCLASS32, ELFCLASS64].include?(ident.getbyte(CLASS_OFFSET))
      return unless [ELFDATA2LSB, ELFDATA2MSB].include?(ident.getbyte(DATA_OFFSET))

      elf64 = ident.getbyte(CLASS_OFFSET) == ELFCLASS64
      # `unpack` directives for the specification's Elf_Half, Elf_Word and
      # Elf_Xword in the file's byte order. Elf_Addr and Elf_Off are a word in
      # 32-bit files and an xword in 64-bit ones.
      half, word, xword = (ident.getbyte(DATA_OFFSET) == ELFDATA2LSB) ? ["v", "V", "Q<"] : ["n", "N", "Q>"]
      address = elf64 ? xword : word

      # The ELF header after e_ident and each program header, field by field in
      # the specification's order. 64-bit program headers move p_flags up to keep
      # the 8-byte fields aligned.
      header_layout = {
        e_type: half, e_machine: half, e_version: word, e_entry: address, e_phoff: address, e_shoff: address,
        e_flags: word, e_ehsize: half, e_phentsize: half, e_phnum: half, e_shentsize: half, e_shnum: half,
        e_shstrndx: half
      }
      program_header_layout = if elf64
        { p_type: word, p_flags: word, p_offset: xword, p_vaddr: xword, p_paddr: xword, p_filesz: xword,
          p_memsz: xword, p_align: xword }
      else
        { p_type: word, p_offset: word, p_vaddr: word, p_paddr: word, p_filesz: word, p_memsz: word,
          p_flags: word, p_align: word }
      end
      header_bytesize = elf64 ? ELF64_HEADER_BYTESIZE : ELF32_HEADER_BYTESIZE
      program_header_bytesize = elf64 ? ELF64_PROGRAM_HEADER_BYTESIZE : ELF32_PROGRAM_HEADER_BYTESIZE

      header = read_fields(file, IDENT_BYTESIZE, header_bytesize - IDENT_BYTESIZE, header_layout)
      program_header_count = header.fetch(:e_phnum)
      # With PN_XNUM, the real count is in the first section header.
      return if program_header_count == PN_XNUM
      return if program_header_count.positive? && header.fetch(:e_phentsize) != program_header_bytesize

      program_headers = Array.new(program_header_count) do |index|
        offset = header.fetch(:e_phoff) + (index * program_header_bytesize)
        read_fields(file, offset, program_header_bytesize, program_header_layout)
      end

      # Like elftools, use the first program header of each type.
      interpreter_header = program_headers.find { |program_header| program_header.fetch(:p_type) == PT_INTERP }
      interpreter = if interpreter_header
        # Drop the last byte, which should be a NUL, as elftools does.
        read_bytes(file, interpreter_header.fetch(:p_offset), interpreter_header.fetch(:p_filesz))[0..-2]
      end
      dynamic_header = program_headers.find { |program_header| program_header.fetch(:p_type) == PT_DYNAMIC }
      if dynamic_header.nil?
        return Fields.new(dynamic_elf: false, dylib_id: nil, needed: [], interpreter:, rpath: nil, dt_flags_1: nil)
      end

      # The dynamic section's [d_tag, d_val] pairs up to DT_NULL. Like elftools,
      # use the first entry for each tag, which is the one `assoc` finds.
      entries = read_bytes(file, dynamic_header.fetch(:p_offset), dynamic_header.fetch(:p_filesz))
                .unpack("#{address}*").map { |value| Integer(value) }.each_slice(2).to_a
      return unless (null_index = entries.index { |d_tag, _| d_tag == DT_NULL })

      entries = entries.first(null_index)
      return unless (strtab = entries.assoc(DT_STRTAB)&.last)

      # Map the string table's address to a file offset as elftools does.
      strtab_header = program_headers.find do |program_header|
        p_vaddr = program_header.fetch(:p_vaddr)
        program_header.fetch(:p_type) == PT_LOAD &&
          strtab >= [p_vaddr & -program_header.fetch(:p_align), p_vaddr - program_header.fetch(:p_offset)].max &&
          strtab < p_vaddr + program_header.fetch(:p_filesz)
      end
      return if strtab_header.nil?

      strtab_offset = strtab - strtab_header.fetch(:p_vaddr) + strtab_header.fetch(:p_offset)
      soname_index = entries.assoc(DT_SONAME)&.last
      rpath_index = (entries.assoc(DT_RUNPATH) || entries.assoc(DT_RPATH))&.last
      needed_indexes = entries.filter_map { |d_tag, d_val| d_val if d_tag == DT_NEEDED }
      Fields.new(
        dynamic_elf: true,
        dylib_id:    (read_string(file, strtab_offset + soname_index) if soname_index),
        needed:      needed_indexes.map { |index| read_string(file, strtab_offset + index) },
        interpreter:,
        rpath:       (read_string(file, strtab_offset + rpath_index) if rpath_index),
        dt_flags_1:  entries.assoc(DT_FLAGS_1)&.last,
      )
    rescue EOFError
      nil
    end

    sig { params(file: File, offset: Integer, bytesize: Integer).returns(String) }
    def read_bytes(file, offset, bytesize)
      raise EOFError if offset + bytesize > file.size

      file.pread(bytesize, offset)
    end

    # Reads the integer fields `layout` names, in order, from `bytesize` bytes at
    # `offset`, where `layout` maps each field's name to its `unpack` directive.
    sig {
      params(file: File, offset: Integer, bytesize: Integer, layout: T::Hash[Symbol, String])
        .returns(T::Hash[Symbol, Integer])
    }
    def read_fields(file, offset, bytesize, layout)
      values = read_bytes(file, offset, bytesize).unpack(layout.values.join)
      layout.keys.zip(values).to_h { |name, value| [name, Integer(value)] }
    end

    sig { params(file: File, offset: Integer).returns(String) }
    def read_string(file, offset)
      raise EOFError if offset >= file.size

      file.seek(offset)
      string = file.gets("\0").to_s
      raise EOFError unless string.end_with?("\0")

      string.chop!
      # elftools returns ASCII strings as UTF-8.
      string.force_encoding(Encoding::UTF_8) if string.ascii_only?
      string
    end

    sig { returns(Fields) }
    def read_using_patchelf_rb
      patcher = path.patchelf_patcher
      dynamic_segment = patcher.elf.segment_by_type(:dynamic)
      dynamic_elf = dynamic_segment.present?
      dylib_id, needed = if dynamic_elf
        [patcher.soname, patcher.needed]
      else
        [nil, []]
      end
      Fields.new(dynamic_elf:, dylib_id:, needed:, interpreter: patcher.interpreter,
                 rpath: patcher.runpath || patcher.rpath, dt_flags_1: dynamic_segment&.tag_by_type(:flags_1)&.value)
    end

    sig { params(basename: String).returns(::Pathname) }
    def find_full_lib_path(basename)
      basename = ::Pathname.new(basename)
      local_paths = rpath&.split(":")

      # Search for dependencies in the runpath/rpath first
      local_paths&.each do |local_path|
        local_path = OS::Linux::Elf.expand_elf_dst(local_path, "ORIGIN", path.parent)
        candidate = ::Pathname.new(local_path)/basename
        elf_candidate = ELFPathname.wrap(candidate)
        return candidate if candidate.exist? && elf_candidate.elf?
      end

      # Check if DF_1_NODEFLIB is set
      nodeflib_flag = if @dt_flags_1.nil?
        false
      else
        @dt_flags_1.anybits?(DF_1_NODEFLIB)
      end

      linker_library_paths = OS::Linux::Ld.library_paths
      linker_system_dirs = OS::Linux::Ld.system_dirs

      # If DF_1_NODEFLIB is set, exclude any library paths that are subdirectories
      # of the system dirs
      if nodeflib_flag
        linker_library_paths = linker_library_paths.reject do |lib_path|
          linker_system_dirs.any? { |system_dir| Utils::Path.child_of? system_dir, lib_path }
        end
      end

      # If not found, search recursively in the paths listed in ld.so.conf (skipping
      # paths that are subdirectories of the system dirs if DF_1_NODEFLIB is set)
      linker_library_paths.each do |linker_library_path|
        candidate = Pathname(linker_library_path)/basename
        elf_candidate = ELFPathname.wrap(candidate)
        return candidate if candidate.exist? && elf_candidate.elf?
      end

      # If not found, search in the system dirs, unless DF_1_NODEFLIB is set
      unless nodeflib_flag
        linker_system_dirs.each do |linker_system_dir|
          candidate = Pathname(linker_system_dir)/basename
          elf_candidate = ELFPathname.wrap(candidate)
          return candidate if candidate.exist? && elf_candidate.elf?
        end
      end

      basename
    end
  end
  private_constant :Metadata

  sig { params(new_interpreter: T.nilable(String), new_rpath: T.nilable(String)).void }
  def save_using_patchelf_rb(new_interpreter, new_rpath)
    patcher = patchelf_patcher
    patcher.interpreter = new_interpreter if new_interpreter.present?
    patcher.rpath = new_rpath if new_rpath.present?
    patcher.save(patchelf_compatible: true)
  end

  # Don't cache the patcher; it keeps the ELF file open so long as it is alive.
  # Instead, for read-only access to the ELF file's metadata, fetch it and cache
  # it with {Metadata}.
  # PatchELF is loaded lazily inside this method, so avoid evaluating its return
  # type at runtime before the constant is defined.
  T::Sig::WithoutRuntime.sig { returns(::PatchELF::Patcher) }
  def patchelf_patcher
    require "patchelf"
    ::PatchELF::Patcher.new to_s, on_error: :silent
  end

  sig { returns(Metadata) }
  def metadata
    @metadata ||= Metadata.new(self)
  end
  private :metadata

  sig { returns(T.nilable(String)) }
  def dylib_id
    metadata.dylib_id
  end

  sig { params(except: Symbol, resolve_variable_references: T::Boolean).returns(T::Array[String]) }
  def dynamically_linked_libraries(except: :none, resolve_variable_references: true)
    metadata.dylibs
  end
end
require "os/linux/elf/os"
