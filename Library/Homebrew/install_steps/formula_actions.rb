# typed: strict
# frozen_string_literal: true

module Homebrew
  module InstallSteps
    class Runner
      private

      sig { void }
      def run_configure_gcc_runtime
        return unless Homebrew::SimulateSystem.simulating_or_running_on_linux?

        version_string = context_version
        raise ArgumentError, "GCC runtime configuration requires a version" if version_string.nil?

        version_major = Version.new(version_string).major.to_s
        gcc = context_path("bin")/"gcc-#{version_major}"
        libgcc = Pathname(run_command_output(gcc, "-print-libgcc-file-name").strip).dirname
        require "utils/path"

        glibc_installed = Utils::Path.formula_any_version_installed?("glibc")
        glibc_lib = Utils::Path.formula_opt_lib("glibc")
        crtdir = if glibc_installed
          glibc_lib
        else
          Pathname(run_command_output("/usr/bin/cc", "-print-file-name=crti.o").strip).dirname
        end
        FileUtils.ln_sf Dir[crtdir/"*crt?.o"], libgcc

        specs = libgcc/"specs"
        ohai "Creating the GCC specs file: #{specs}"
        FileUtils.rm_f ["#{specs}.orig", specs]
        system_header_dirs = [HOMEBREW_PREFIX/"include"]
        if glibc_installed
          system_header_dirs << Utils::Path.formula_opt_include("glibc")
        else
          target = run_command_output(gcc, "-print-multiarch").strip
          system_header_dirs += [Pathname("/usr/include")/target, Pathname("/usr/include")]
        end

        specs_string = run_command_output(gcc, "-dumpspecs")
        Pathname("#{specs}.orig").write specs_string
        libdir = if context_name == "gcc"
          HOMEBREW_PREFIX/"lib/gcc/current"
        else
          HOMEBREW_PREFIX/"lib/gcc"/version_major
        end
        link_libgcc = glibc_installed ? "-nostdlib -L#{libgcc} -L#{glibc_lib}" : "+"
        homebrew_rpath = version_major.to_i >= 11
        specs.write specs_string + <<~EOS
          *cpp_unique_options:
          + -isysroot #{HOMEBREW_PREFIX}/nonexistent #{system_header_dirs.map { |p| "-idirafter #{p}" }.join(" ")}

          *link_libgcc:
          #{link_libgcc} -L#{libdir} -L#{HOMEBREW_PREFIX}/lib

          *link:
          + --dynamic-linker #{HOMEBREW_PREFIX}/lib/ld.so -rpath #{libdir}#{" -rpath #{HOMEBREW_PREFIX}/lib" unless homebrew_rpath}

          #{"*homebrew_rpath:\n-rpath #{HOMEBREW_PREFIX}/lib\n" if homebrew_rpath}
        EOS
        specs.write(specs.read.gsub(" %o ", "\\0%(homebrew_rpath) ")) if homebrew_rpath
      end

      sig { params(step: Step).void }
      def run_install_gzipped_executable(step)
        source = resolve_path(step_path(step, "source"))
        return unless source.exist?

        require "unpack_strategy"

        target = resolve_path(step_path(step, "target"))
        target.dirname.mkpath
        temporary_target = target.dirname/".#{target.basename}.install-step"
        temporary_gzip = Pathname("#{temporary_target}.gz")
        FileUtils.rm_f [temporary_target, temporary_gzip]
        begin
          UnpackStrategy::Gzip.new(source).extract(to: target.dirname, basename: temporary_gzip.basename)
          FileUtils.rm_f target
          FileUtils.mv temporary_target, target
          source.unlink
        ensure
          FileUtils.rm_f [temporary_target, temporary_gzip]
        end
        target.chmod 0755
      end

      sig { void }
      def run_configure_glibc_runtime
        (context_path("lib")/"locale").mkpath
        legacy_formula = context_name != "glibc"
        locales = ENV.filter_map do |key, value|
          next unless key.match?(legacy_formula ? /^LANG$|^LC_/ : /^HOMEBREW_LANG$|^LANG$|^LC_/)
          next if value == "C" || (legacy_formula && value.start_with?("C."))

          value
        end
        locales = (locales + ["en_US.UTF-8"]).sort.uniq
        ohai "Installing locale data for #{locales.join(" ")}"
        locales.each do |locale|
          lang, charmap = locale.split(".", 2)
          next if lang.nil?

          if charmap.present?
            charmap = "UTF-8" if charmap == "utf8"
            run_command context_path("bin")/"localedef", "-i", lang, "-f", charmap, locale
          else
            run_command context_path("bin")/"localedef", "-i", lang, locale
          end
        end

        [[Pathname("/etc/localtime"), context_path("etc")/"localtime"],
         [Pathname("/usr/share/zoneinfo"), context_path("share")/"zoneinfo"]].each do |source, target|
          File.symlink source, target if source.exist? && !target.exist?
        end
      end

      sig { void }
      def run_configure_clang_system
        return unless Homebrew::SimulateSystem.simulating_or_running_on_macos?

        macos_version = MacOS.version
        kernel_version = OS.kernel_version.major
        raise ArgumentError, "Clang system configuration requires a kernel version" if kernel_version.nil?

        kernel_version = kernel_version.to_s
        arch = Hardware::CPU.arch
        config_dir = context_path("etc")/"clang"
        return if ["darwin#{kernel_version}", "macosx#{macos_version}"].all? do |system|
          (config_dir/"#{arch}-apple-#{system}.cfg").exist?
        end

        require "utils/clang"
        Utils::Clang.write_system_config_files(config_dir:, macos_version:, kernel_version:, arch:)
      end
    end
  end
end
