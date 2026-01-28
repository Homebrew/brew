# typed: strict
# frozen_string_literal: true

require "compilers"

module OS
  module Linux
    module Keg
      extend T::Helpers

      requires_ancestor { ::Keg }

      sig { params(relocation: ::Keg::Relocation, skip_protodesc_cold: T::Boolean).void }
      def relocate_dynamic_linkage(relocation, skip_protodesc_cold: false)
        # Patching the dynamic linker of glibc breaks it.
        return if name.match? Version.formula_optionally_versioned_regex(:glibc)

        old_prefix, new_prefix = relocation.replacement_pair_for(:prefix)

        elf_files.each do |file|
          file.ensure_writable do
            change_rpath!(file, old_prefix, new_prefix, skip_protodesc_cold:)
          end
        end
      end

      sig {
        params(file: ELFShim, old_prefix: T.any(String, Regexp), new_prefix: String,
               skip_protodesc_cold: T::Boolean).returns(T::Boolean)
      }
      def change_rpath!(file, old_prefix, new_prefix, skip_protodesc_cold: false)
        return false if !file.elf? || !file.dynamic_elf?

        # Skip relocation of files with `protodesc_cold` sections because patchelf.rb seems to break them,
        # but only when bottling (as we don't want to break existing bottles that require relocation).
        # https://github.com/Homebrew/homebrew-core/pull/232490#issuecomment-3161362452
        return false if skip_protodesc_cold && file.section_names.include?("protodesc_cold")

        updated = {}
        old_rpath = file.rpath
        new_rpath = if old_rpath
          rpath = old_rpath.split(":")
                           .map { |x| x.sub(old_prefix, new_prefix) }
                           .select { |x| x.start_with?(new_prefix, "$ORIGIN") }

          lib_path = "#{new_prefix}/lib"
          rpath << lib_path unless rpath.include? lib_path

          # Add GCC's lib directory (as of GCC 12+) to RPATH when there is existing versioned linkage.
          # This prevents broken linkage when pouring bottles built with an old GCC formula.
          unless name.match?(Version.formula_optionally_versioned_regex(:gcc))
            rpath.map! { |rp| rp.sub(%r{lib/gcc/\d+$}, "lib/gcc/current") }
          end

          rpath.join(":")
        end
        updated[:rpath] = new_rpath if old_rpath != new_rpath

        old_interpreter = file.interpreter
        new_interpreter = if old_interpreter.nil?
          nil
        elsif File.readable? "#{new_prefix}/lib/ld.so"
          "#{new_prefix}/lib/ld.so"
        else
          old_interpreter.sub old_prefix, new_prefix
        end
        updated[:interpreter] = new_interpreter if old_interpreter != new_interpreter

        file.patch!(interpreter: updated[:interpreter], rpath: updated[:rpath])
        true
      end

      sig { params(options: T::Hash[Symbol, T::Boolean]).returns(T::Array[Symbol]) }
      def detect_cxx_stdlibs(options = {})
        skip_executables = options.fetch(:skip_executables, false)
        results = Set.new
        elf_files.each do |file|
          next unless file.dynamic_elf?
          next if file.binary_executable? && skip_executables

          dylibs = file.dynamically_linked_libraries
          results << :libcxx if dylibs.any? { |s| s.include? "libc++.so" }
          results << :libstdcxx if dylibs.any? { |s| s.include? "libstdc++.so" }
        end
        results.to_a
      end

      sig { returns(T::Array[ELFShim]) }
      def elf_files
        hardlinks = Set.new
        elf_files = []
        path.find do |pn|
          next if pn.symlink? || pn.directory?

          pn = ELFPathname.wrap(pn)
          next if !pn.dylib? && !pn.binary_executable?

          # If we've already processed a file, ignore its hardlinks (which have the
          # same dev ID and inode). This prevents relocations from being performed
          # on a binary more than once.
          next unless hardlinks.add? [pn.stat.dev, pn.stat.ino]

          elf_files << pn
        end
        elf_files
      end
    end
  end
end

Keg.prepend(OS::Linux::Keg)
