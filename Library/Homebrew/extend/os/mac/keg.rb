# typed: strict
# frozen_string_literal: true

require "system_command"

module OS
  module Mac
    module Keg
      include SystemCommand::Mixin

      module ClassMethods
        sig { returns(T::Array[String]) }
        def keg_link_directories
          @keg_link_directories ||= T.let((super + ["Frameworks"]).freeze, T.nilable(T::Array[String]))
        end

        sig { returns(T::Array[::Pathname]) }
        def must_exist_subdirectories
          @must_exist_subdirectories ||= T.let((
            super +
            [HOMEBREW_PREFIX/"Frameworks"]
          ).sort.uniq.freeze, T.nilable(T::Array[::Pathname]))
        end

        sig { returns(T::Array[::Pathname]) }
        def must_exist_directories
          @must_exist_directories ||= T.let((
            super +
            [HOMEBREW_PREFIX/"Frameworks"]
          ).sort.uniq.freeze, T.nilable(T::Array[::Pathname]))
        end

        sig { returns(T::Array[::Pathname]) }
        def must_be_writable_directories
          @must_be_writable_directories ||= T.let((
            super +
            [HOMEBREW_PREFIX/"Frameworks"]
          ).sort.uniq.freeze, T.nilable(T::Array[::Pathname]))
        end
      end

      sig { params(path: ::Pathname).void }
      def initialize(path)
        super

        @require_relocation = T.let(false, T::Boolean)
      end

      sig { params(id: String, file: MachOShim).returns(T::Boolean) }
      def change_dylib_id(id, file)
        return false if file.dylib_id == id

        @require_relocation = true
        odebug "Changing dylib ID of #{file}\n  from #{file.dylib_id}\n    to #{id}"
        file.change_dylib_id(id, strict: false)
        true
      rescue MachO::MachOError
        onoe <<~EOS
          Failed changing dylib ID of #{file}
            from #{file.dylib_id}
              to #{id}
        EOS
        raise
      end

      sig { params(old: String, new: String, file: MachOShim).returns(T::Boolean) }
      def change_install_name(old, new, file)
        return false if old == new

        @require_relocation = true
        odebug "Changing install name in #{file}\n  from #{old}\n    to #{new}"
        file.change_install_name(old, new, strict: false)
        true
      rescue MachO::MachOError
        onoe <<~EOS
          Failed changing install name in #{file}
            from #{old}
              to #{new}
        EOS
        raise
      end

      sig { params(old: String, new: String, file: MachOShim).returns(T::Boolean) }
      def change_rpath(old, new, file)
        return false if old == new

        @require_relocation = true
        odebug "Changing rpath in #{file}\n  from #{old}\n    to #{new}"
        file.change_rpath(old, new, strict: false)
        true
      rescue MachO::MachOError
        onoe <<~EOS
          Failed changing rpath in #{file}
            from #{old}
              to #{new}
        EOS
        raise
      end

      sig { params(rpath: String, file: MachOShim).returns(T::Boolean) }
      def delete_rpath(rpath, file)
        odebug "Deleting rpath #{rpath} in #{file}"
        file.delete_rpath(rpath, strict: false)
        true
      rescue MachO::MachOError
        onoe <<~EOS
          Failed deleting rpath #{rpath} in #{file}
        EOS
        raise
      end

      sig { returns(T::Array[MachOShim]) }
      def binary_executable_or_library_files = mach_o_files

      sig { params(file: String).void }
      def codesign_patched_binary(file)
        return if MacOS.version < :big_sur

        unless ::Hardware::CPU.arm?
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

      sig { params(file: String, _block: T.proc.void).void }
      def prepare_codesign_writable_files(file, &_block)
        result = system_command("codesign", args: [
          "--display", "--file-list", "-", file
        ], print_stderr: false)
        return unless result.success?

        files = result.stdout.lines.map { |f| Pathname(f.chomp) }
        saved_perms = {}
        files.each do |f|
          unless f.writable?
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

      sig { void }
      def prepare_debug_symbols
        binary_executable_or_library_files.each do |file|
          file = file.to_s
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

      # Needed to make symlink permissions consistent on macOS and Linux for
      # reproducible bottles.
      sig { void }
      def consistent_reproducible_symlink_permissions!
        path.find do |file|
          file.lchmod 0777 if file.symlink?
        end
      end
    end
  end
end

Keg.singleton_class.prepend(OS::Mac::Keg::ClassMethods)
Keg.prepend(OS::Mac::Keg)
