# typed: true
# frozen_string_literal: true

require "os/linux/ld"

# {Pathname} extension for dealing with ELF files.
# @see https://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_header
#
# @api private
module ELFShim
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
  ARCHITECTURE_ARM = 0x28
  private_constant :ARCHITECTURE_ARM
  ARCHITECTURE_X86_64 = 0x3E
  private_constant :ARCHITECTURE_X86_64
  ARCHITECTURE_AARCH64 = 0xB7
  private_constant :ARCHITECTURE_AARCH64

  def read_uint8(offset)
    read(1, offset).unpack1("C")
  end

  def read_uint16(offset)
    read(2, offset).unpack1("v")
  end

  def elf?
    return @elf if defined? @elf
    return @elf = false if read(MAGIC_NUMBER_ASCII.size, MAGIC_NUMBER_OFFSET) != MAGIC_NUMBER_ASCII

    # Check that this ELF file is for Linux or System V.
    # OS_ABI is often set to 0 (System V), regardless of the target platform.
    @elf = [OS_ABI_LINUX, OS_ABI_SYSTEM_V].include? read_uint8(OS_ABI_OFFSET)
  end

  def arch
    return :dunno unless elf?

    @arch ||= case read_uint16(ARCHITECTURE_OFFSET)
    when ARCHITECTURE_I386 then :i386
    when ARCHITECTURE_X86_64 then :x86_64
    when ARCHITECTURE_POWERPC then :powerpc
    when ARCHITECTURE_ARM then :arm
    when ARCHITECTURE_AARCH64 then :arm64
    else :dunno
    end
  end

  def elf_type
    return :dunno unless elf?

    @elf_type ||= case read_uint16(TYPE_OFFSET)
    when TYPE_EXECUTABLE then :executable
    when TYPE_SHARED then :dylib
    else :dunno
    end
  end

  def dylib?
    elf_type == :dylib
  end

  def binary_executable?
    elf_type == :executable
  end

  # The runtime search path, such as:
  # "/lib:/usr/lib:/usr/local/lib"
  def rpath
    return @rpath if defined? @rpath

    @rpath = rpath_using_patchelf_rb
  end

  # An array of runtime search path entries, such as:
  # ["/lib", "/usr/lib", "/usr/local/lib"]
  def rpaths
    Array(rpath&.split(":"))
  end

  def interpreter
    return @interpreter if defined? @interpreter

    @interpreter = patchelf_patcher.interpreter
  end

  def patch!(interpreter: nil, rpath: nil)
    return if interpreter.blank? && rpath.blank?

    save_using_patchelf_rb interpreter, rpath
  end

  def dynamic_elf?
    return @dynamic_elf if defined? @dynamic_elf

    @dynamic_elf = patchelf_patcher.elf.segment_by_type(:DYNAMIC).present?
  end

  # Helper class for reading metadata from an ELF file.
  #
  # @api private
  class Metadata
    attr_reader :path, :dylib_id, :dylibs

    def initialize(path)
      @path = path
      @dylibs = []
      @dylib_id, needed = needed_libraries path
      return if needed.empty?

      @dylibs = needed.map { |lib| find_full_lib_path(lib).to_s }
    end

    private

    def needed_libraries(path)
      return [nil, []] unless path.dynamic_elf?

      needed_libraries_using_patchelf_rb path
    end

    def needed_libraries_using_patchelf_rb(path)
      patcher = path.patchelf_patcher
      [patcher.soname, patcher.needed]
    end

    def find_full_lib_path(basename)
      local_paths = (path.patchelf_patcher.runpath || path.patchelf_patcher.rpath)&.split(":")

      # Search for dependencies in the runpath/rpath first
      local_paths&.each do |local_path|
        candidate = Pathname(local_path)/basename
        return candidate if candidate.exist? && candidate.elf?
      end

      # Check if DF_1_NODEFLIB is set
      dt_flags_1 = path.patchelf_patcher.elf.segment_by_type(:dynamic)&.tag_by_type(:flags_1)
      nodeflib_flag = if dt_flags_1.nil?
        false
      else
        dt_flags_1.value & ELFTools::Constants::DF::DF_1_NODEFLIB != 0
      end

      linker_library_paths = OS::Linux::Ld.library_paths
      linker_system_dirs = OS::Linux::Ld.system_dirs

      # If DF_1_NODEFLIB is set, exclude any library paths that are subdirectories
      # of the system dirs
      if nodeflib_flag
        linker_library_paths = linker_library_paths.reject do |linker_library_path|
          child = Pathname(linker_library_path).realdirpath

          linker_system_dirs.any? do |linker_system_dir|
            parent = Pathname(linker_system_dir).realdirpath
            child.child_of? parent
          end
        end
      end

      # If not found, search recursively in the paths listed in ld.so.conf (skipping
      # paths that are subdirectories of the system dirs if DF_1_NODEFLIB is set)
      linker_library_paths.each do |linker_library_path|
        candidate = Pathname(linker_library_path)/basename
        return candidate if candidate.exist? && candidate.elf?
      end

      # If not found, search in the system dirs, unless DF_1_NODEFLIB is set
      unless nodeflib_flag
        linker_system_dirs.each do |linker_system_dir|
          candidate = Pathname(linker_system_dir)/basename
          return candidate if candidate.exist? && candidate.elf?
        end
      end

      basename
    end
  end
  private_constant :Metadata

  def save_using_patchelf_rb(new_interpreter, new_rpath)
    patcher = patchelf_patcher
    patcher.interpreter = new_interpreter if new_interpreter.present?
    patcher.rpath = new_rpath if new_rpath.present?
    patcher.save(patchelf_compatible: true)
  end

  def rpath_using_patchelf_rb
    patchelf_patcher.runpath || patchelf_patcher.rpath
  end

  def patchelf_patcher
    require "patchelf"
    @patchelf_patcher ||= ::PatchELF::Patcher.new to_s, on_error: :silent
  end

  def metadata
    @metadata ||= Metadata.new(self)
  end
  private :metadata

  def dylib_id
    metadata.dylib_id
  end

  def dynamically_linked_libraries(*)
    metadata.dylibs
  end
end
