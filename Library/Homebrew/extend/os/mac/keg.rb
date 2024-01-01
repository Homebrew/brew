# typed: true
# frozen_string_literal: true

class Keg
  GENERIC_KEG_LINK_DIRECTORIES = (remove_const :KEG_LINK_DIRECTORIES).freeze
  KEG_LINK_DIRECTORIES = (GENERIC_KEG_LINK_DIRECTORIES + ["Frameworks"]).freeze
  GENERIC_MUST_EXIST_SUBDIRECTORIES = (remove_const :MUST_EXIST_SUBDIRECTORIES).freeze
  MUST_EXIST_SUBDIRECTORIES = (
    GENERIC_MUST_EXIST_SUBDIRECTORIES +
    [HOMEBREW_PREFIX/"Frameworks"]
  ).sort.uniq.freeze
  GENERIC_MUST_EXIST_DIRECTORIES = (remove_const :MUST_EXIST_DIRECTORIES).freeze
  MUST_EXIST_DIRECTORIES = (
    GENERIC_MUST_EXIST_DIRECTORIES +
    [HOMEBREW_PREFIX/"Frameworks"]
  ).sort.uniq.freeze
  GENERIC_MUST_BE_WRITABLE_DIRECTORIES = (remove_const :MUST_BE_WRITABLE_DIRECTORIES).freeze
  MUST_BE_WRITABLE_DIRECTORIES = (
    GENERIC_MUST_BE_WRITABLE_DIRECTORIES +
    [HOMEBREW_PREFIX/"Frameworks"]
  ).sort.uniq.freeze

  undef binary_executable_or_library_files

  def binary_executable_or_library_files
    mach_o_files
  end

  def codesign_patched_binary(file)
    return if MacOS.version < :big_sur

    unless Hardware::CPU.arm?
      result = system_command("codesign", args: ["--verify", file], print_stderr: false)
      return unless result.stderr.match?(/invalid signature/i)
    end

    odebug "Codesigning #{file}"
    prepare_codesign_writable_files(file) do
      # Use quiet_system to squash notifications about resigning binaries
      # which already have valid signatures.
      return if quiet_system("codesign", "--sign", "-", "--force",
                             "--preserve-metadata=entitlements,requirements,flags,runtime",
                             file)

      # If the codesigning fails, it may be a bug in Apple's codesign utility
      # A known workaround is to copy the file to another inode, then move it back
      # erasing the previous file. Then sign again.
      #
      # TODO: remove this once the bug in Apple's codesign utility is fixed
      Dir::Tmpname.create("workaround") do |tmppath|
        FileUtils.cp file, tmppath
        FileUtils.mv tmppath, file, force: true
      end

      # Try signing again
      odebug "Codesigning (2nd try) #{file}"
      result = system_command("codesign", args: [
        "--sign", "-", "--force",
        "--preserve-metadata=entitlements,requirements,flags,runtime",
        file
      ], print_stderr: false)
      return if result.success?

      # If it fails again, error out
      onoe <<~EOS
        Failed applying an ad-hoc signature to #{file}:
        #{result.stderr}
      EOS
    end
  end

  def prepare_codesign_writable_files(file)
    result = system_command("codesign", args: [
      "--display", "--file-list", "-", file
    ], print_stderr: false)
    return unless result.success?

    files = result.stdout.lines.map { |f| Pathname(f.chomp) }
    saved_perms = {}
    files.each do |f|
      unless f.writable_real?
        saved_perms[f] = f.stat.mode
        FileUtils.chmod "u+rw", f.to_path
      end
    end
    yield
  ensure
    saved_perms&.each do |f, p|
      f.chmod p if p
    end
  end

  undef prepare_debug_symbols

  def prepare_debug_symbols
    binary_executable_or_library_files.each do |file|
      odebug "Extracting symbols #{file}"

      result = system_command("dsymutil", args: [file], print_stderr: false)
      next if result.success?

      # If it fails again, error out
      ofail <<~EOS
        Failed to extract symbols from #{file}:
        #{result.stderr}
      EOS
    end
  end

  undef consistent_reproducible_symlink_permissions!

  # Needed to make symlink permissions consistent on macOS and Linux for
  # reproducible bottles.
  def consistent_reproducible_symlink_permissions!
    path.find do |file|
      File.lchmod 0777, file if file.symlink?
    end
  end
end
