# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Keg
      extend T::Helpers

      requires_ancestor { ::Keg }

      module ClassMethods
        sig { params(file: ::Pathname, string: String).returns(T::Array[String]) }
        def file_linked_libraries(file, string)
          file = MachOPathname.wrap(file)

          # Check dynamic library linkage. Importantly, do not perform for static
          # libraries, which will falsely report "linkage" to themselves.
          # Only the raw load-command names matter: resolving `@rpath` or
          # `@loader_path` references against the live keg turns
          # relocatable-by-construction linkage into absolute build-prefix
          # paths and wrongly pins bottles, while genuinely unplaceholdered
          # names contain the prefix in their raw form already.
          if file.mach_o_executable? || file.dylib? || file.mach_o_bundle?
            file.dynamically_linked_libraries(resolve_variable_references: false).select { |lib| lib.include? string }
          else
            []
          end
        end
      end

      sig {
        params(relocation: ::Keg::Relocation, with_placeholders: T::Boolean,
               files: T.nilable(T::Array[::Pathname])).returns(T::Array[::Pathname])
      }
      def relocate_dynamic_linkage(relocation, with_placeholders: false, files: nil)
        candidates = if files
          # Metadata-driven pour: only the files recorded at bottle time carry
          # placeholdered linkage, so skip the whole-keg walk.
          keg_files(files).map { |file| MachOPathname.wrap(file) }
        else
          mach_o_files
        end

        linkage_files = []
        candidates.each do |file|
          Utils::Path.ensure_writable(file.to_path) do
            modified = T.let(false, T::Boolean)

            if file.dylib? && (dylib_id = file.dylib_id) && (id = relocated_name_for(dylib_id, relocation))
              modified = change_dylib_id(id, file, write: false) || modified
            end

            each_linkage_for(file, :dynamically_linked_libraries) do |old_name|
              new_name = relocated_name_for(old_name, relocation)
              modified = change_install_name(old_name, new_name, file, write: false) || modified if new_name
            end

            each_linkage_for(file, :rpaths) do |old_name|
              new_name = relocated_name_for(old_name, relocation)
              modified = change_rpath(old_name, new_name, file, write: false) || modified if new_name
            end

            next unless modified

            # The edits above only mutated the in-memory Mach-O, so persist
            # them in a single write per file.
            file.save_changes
            linkage_files << file.relative_path_from(path)
          end
        end

        # Every saved file's signature is now broken, so re-sign each exactly
        # once, parallelised across files.
        codesign_patched_binaries(linkage_files.map { path/it })
        linkage_files
      end

      sig { void }
      def fix_dynamic_linkage
        fixed_files = []
        mach_o_files.each do |file|
          Utils::Path.ensure_writable(file.to_path) do
            modified = T.let(false, T::Boolean)

            modified = change_dylib_id(dylib_id_for(file), file, write: false) if file.dylib?

            each_linkage_for(file, :dynamically_linked_libraries) do |bad_name|
              # Don't fix absolute paths unless they are rooted in the build directory.
              new_name = if bad_name.start_with?("/") && !rooted_in_build_directory?(bad_name)
                bad_name
              else
                fixed_name(file, bad_name)
              end
              loader_name = loader_name_for(file, new_name)
              if loader_name != bad_name
                modified = change_install_name(bad_name, loader_name, file,
                                               write: false) || modified
              end
            end

            each_linkage_for(file, :rpaths) do |bad_name|
              new_name = opt_name_for(bad_name)
              loader_name = loader_name_for(file, new_name)
              next if loader_name == bad_name

              modified = change_rpath(bad_name, loader_name, file, write: false) || modified
            end

            # Strip duplicate rpaths and rpaths rooted in the build directory.
            # We do this separately from the rpath relocation above to avoid
            # failing to relocate an rpath whose variable duplicate we deleted.
            each_linkage_for(file, :rpaths, resolve_variable_references: true) do |bad_name|
              next if !rooted_in_build_directory?(bad_name) && file.rpaths.count(bad_name) == 1

              modified = delete_rpath(bad_name, file, write: false) || modified
            end

            next unless modified

            # The edits above only mutated the in-memory Mach-O, so persist
            # them in a single write per file.
            file.save_changes
            fixed_files << file
          end
        end

        # Every saved file's signature is now broken, so re-sign each exactly
        # once, parallelised across files.
        codesign_patched_binaries(fixed_files)

        super
      end

      sig { params(file: MachOShim, target: String).returns(String) }
      def loader_name_for(file, target)
        # Use @loader_path-relative install names for other Homebrew-installed binaries.
        if ENV["HOMEBREW_RELOCATABLE_INSTALL_NAMES"] && target.start_with?(HOMEBREW_PREFIX)
          dylib_suffix = find_dylib_suffix_from(target)
          target_dir = ::Pathname.new(target.delete_suffix(dylib_suffix)).cleanpath

          "@loader_path/#{target_dir.relative_path_from(file.dirname)/dylib_suffix}"
        else
          target
        end
      end

      # If file is a dylib or bundle itself, look for the dylib named by
      # bad_name relative to the lib directory, so that we can skip the more
      # expensive recursive search if possible.
      sig { params(file: MachOShim, bad_name: String).returns(String) }
      def fixed_name(file, bad_name)
        if bad_name.start_with? ::Keg::PREFIX_PLACEHOLDER
          bad_name.sub(::Keg::PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
        elsif bad_name.start_with? ::Keg::CELLAR_PLACEHOLDER
          bad_name.sub(::Keg::CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
        elsif (file.dylib? || file.mach_o_bundle?) && (file.dirname/bad_name).exist?
          "@loader_path/#{bad_name}"
        elsif file.mach_o_executable? && (lib/bad_name).exist?
          "#{lib}/#{bad_name}"
        elsif file.mach_o_executable? && (libexec/"lib"/bad_name).exist?
          "#{libexec}/lib/#{bad_name}"
        elsif (abs_name = find_dylib(bad_name)) && abs_name.exist?
          abs_name.to_s
        else
          opoo "Could not fix #{bad_name} in #{file}"
          bad_name
        end
      end

      VARIABLE_REFERENCE_RX = /^@(loader_|executable_|r)path/

      sig { params(file: MachOShim, linkage_type: Symbol, resolve_variable_references: T::Boolean, block: T.proc.params(arg0: String).void).void }
      def each_linkage_for(file, linkage_type, resolve_variable_references: false, &block)
        file.public_send(linkage_type, resolve_variable_references:)
            .grep_v(VARIABLE_REFERENCE_RX)
            .each(&block)
      end

      sig { params(file: MachOShim).returns(String) }
      def dylib_id_for(file)
        dylib_id = file.dylib_id
        raise ArgumentError, "#{file} has no dylib ID" if dylib_id.nil?

        # Swift dylib IDs should be /usr/lib/swift
        return dylib_id if dylib_id.start_with?("/usr/lib/swift/libswift")

        # Preserve @rpath install names if the formula has specified preserve_rpath
        return dylib_id if dylib_id.start_with?("@rpath") && formula_preserve_rpath?

        # The new dylib ID should have the same basename as the old dylib ID, not
        # the basename of the file itself.
        basename = File.basename(dylib_id)
        relative_dirname = file.dirname.relative_path_from(path)
        (opt_record/relative_dirname/basename).to_s
      end

      sig { returns(T::Boolean) }
      def formula_preserve_rpath?
        ::Formula[name].preserve_rpath?
      rescue FormulaUnavailableError
        false
      end

      sig { params(old_name: String, relocation: ::Keg::Relocation).returns(T.nilable(String)) }
      def relocated_name_for(old_name, relocation)
        old_prefix, new_prefix = relocation.replacement_pair_for(:prefix)
        old_cellar, new_cellar = relocation.replacement_pair_for(:cellar)

        if old_name.start_with? old_cellar
          old_name.sub(old_cellar, new_cellar)
        elsif old_name.start_with? old_prefix
          old_name.sub(old_prefix, new_prefix)
        end
      end

      # Matches framework references like `XXX.framework/Versions/YYY/XXX` and
      # `XXX.framework/XXX`, both with or without a slash-delimited prefix.
      FRAMEWORK_RX = %r{(?:^|/)(([^/]+)\.framework/(?:Versions/[^/]+/)?\2)$}

      sig { params(bad_name: String).returns(String) }
      def find_dylib_suffix_from(bad_name)
        bad_name[FRAMEWORK_RX, 1] || File.basename(bad_name)
      end

      sig { params(bad_name: String).returns(T.nilable(::Pathname)) }
      def find_dylib(bad_name)
        return unless lib.directory?

        suffix = "/#{find_dylib_suffix_from(bad_name)}"
        lib.find { |pn| break pn if pn.to_s.end_with?(suffix) }
      end

      sig { returns(T::Array[MachOShim]) }
      def mach_o_files
        hardlinks = Set.new
        mach_o_files = []
        path.find do |pn|
          next if pn.symlink? || pn.directory?

          pn = MachOPathname.wrap(pn)
          next if !pn.dylib? && !pn.mach_o_bundle? && !pn.mach_o_executable?

          # if we've already processed a file, ignore its hardlinks (which have the same dev ID and inode)
          # this prevents relocations from being performed on a binary more than once
          next unless hardlinks.add? [pn.stat.dev, pn.stat.ino]

          mach_o_files << pn
        end

        mach_o_files
      end

      sig { returns(::Keg::Relocation) }
      def prepare_relocation_to_locations
        relocation = super

        brewed_perl = runtime_dependencies&.any? do |dep|
          dep = T.cast(dep, T::Hash[String, T.untyped])
          dep["full_name"] == "perl" && dep["declared_directly"]
        end
        perl_path = if brewed_perl || name == "perl"
          "#{HOMEBREW_PREFIX}/opt/perl/bin/perl"
        elsif tab.built_on.present? &&
              (preferred_perl_version = tab.built_on&.[]("preferred_perl")&.presence) &&
              preferred_perl_version.match?(/^\d+\.\d+$/) &&
              (perl_path = "/usr/bin/perl#{preferred_perl_version}") &&
              File.exist?(perl_path)
          perl_path
        else
          "/usr/bin/perl#{MacOS.preferred_perl_version}"
        end
        relocation.add_replacement_pair(:perl, ::Keg::PERL_PLACEHOLDER, perl_path)

        if (openjdk = openjdk_dep_name_if_applicable)
          openjdk_path = HOMEBREW_PREFIX/"opt"/openjdk/"libexec/openjdk.jdk/Contents/Home"
          relocation.add_replacement_pair(:java, ::Keg::JAVA_PLACEHOLDER, openjdk_path.to_s)
        end

        relocation
      end

      sig { returns(String) }
      def recursive_fgrep_args
        # Don't recurse into symlinks; the man page says this is the default, but
        # it's wrong. -O is a BSD-grep-only option.
        "-lrO"
      end

      sig { returns([String, String]) }
      def egrep_args
        grep_bin = "egrep"
        grep_args = "--files-with-matches"
        [grep_bin, grep_args]
      end

      private

      CELLAR_RX = %r{\A#{HOMEBREW_CELLAR}/(?<formula_name>[^/]+)/[^/]+}
      private_constant :CELLAR_RX

      # Replace HOMEBREW_CELLAR references with HOMEBREW_PREFIX/opt references
      # if the Cellar reference is to a different keg.
      sig { params(filename: String).returns(String) }
      def opt_name_for(filename)
        return filename unless filename.start_with?(HOMEBREW_PREFIX.to_s)
        return filename if filename.start_with?(path.to_s)
        return filename if (matches = CELLAR_RX.match(filename)).blank?

        filename.sub(CELLAR_RX, "#{HOMEBREW_PREFIX}/opt/#{matches[:formula_name]}")
      end

      sig { params(filename: String).returns(T::Boolean) }
      def rooted_in_build_directory?(filename)
        # CMake normalises `/private/tmp` to `/tmp`.
        # https://gitlab.kitware.com/cmake/cmake/-/issues/23251
        return true if HOMEBREW_TEMP.to_s == "/private/tmp" && filename.start_with?("/tmp/")

        filename.start_with?(HOMEBREW_TEMP.to_s, HOMEBREW_TEMP.realpath.to_s)
      end
    end
  end
end

Keg.singleton_class.prepend(OS::Mac::Keg::ClassMethods)
Keg.prepend(OS::Mac::Keg)
