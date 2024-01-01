# typed: true
# frozen_string_literal: true

require "compilers"

class LinkageChecker
  # Libraries provided by glibc and gcc.
  SYSTEM_LIBRARY_ALLOWLIST = %w[
    ld-linux-x86-64.so.2
    ld-linux-aarch64.so.1
    libanl.so.1
    libatomic.so.1
    libc.so.6
    libdl.so.2
    libm.so.6
    libmvec.so.1
    libnss_files.so.2
    libpthread.so.0
    libresolv.so.2
    librt.so.1
    libthread_db.so.1
    libutil.so.1
    libgcc_s.so.1
    libgomp.so.1
    libstdc++.so.6
    libquadmath.so.0
  ].freeze

  private

  def check_dylibs(rebuild_cache:)
    generic_check_dylibs(rebuild_cache: rebuild_cache)

    # glibc and gcc are implicit dependencies.
    # No other linkage to system libraries is expected or desired.
    @unwanted_system_dylibs = @system_dylibs.reject do |s|
      SYSTEM_LIBRARY_ALLOWLIST.include? File.basename(s)
    end

    # We build all formulae with an RPATH that includes the gcc formula's runtime lib directory.
    # See: https://github.com/Homebrew/brew/blob/e689cc07/Library/Homebrew/extend/os/linux/extend/ENV/super.rb#L53
    # This results in formulae showing linkage with gcc whenever it is installed, even if no dependency is declared.
    # See discussions at:
    #   https://github.com/Homebrew/brew/pull/13659
    #   https://github.com/Homebrew/brew/pull/13796
    # TODO: Find a nicer way to handle this. (e.g. examining the ELF file to determine the required libstdc++.)
    @undeclared_deps.delete("gcc")
  end
end
