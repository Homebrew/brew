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

      sig { void }
      def run_configure_php
        pear_prefix = context_path("pkgshare")/"pear"
        channels = [pear_prefix/".channels", pear_prefix/".channels/.alias"]
        FileUtils.chmod 0755, channels
        pear_files = %w[.depdblock .filemap .depdb .lock].map { |file| pear_prefix/file }
        pear_files.concat(channels.flat_map(&:children))
        FileUtils.chmod 0644, pear_files

        pecl_path = HOMEBREW_PREFIX/"lib/php/pecl"
        pecl_path.mkpath
        prefix_pecl = context_path("prefix")/"pecl"
        File.symlink pecl_path, prefix_pecl unless prefix_pecl.exist?
        php_basename = File.basename(run_command_output(context_path("bin")/"php-config", "--extension-dir").strip)
        (pecl_path/php_basename).mkpath

        version_string = context_version
        raise ArgumentError, "PHP configuration requires a version" if version_string.nil?

        version_major_minor = Version.new(version_string).major_minor.to_s
        pear_dir = (context_name == "php") ? "pear" : "pear@#{version_major_minor}"
        pear_path = HOMEBREW_PREFIX/"share"/pear_dir
        FileUtils.cp_r "#{pear_prefix}/.", pear_path
        php_ext_dir = context_path("opt_prefix")/"lib/php"/php_basename
        {
          "php_ini"  => context_path("etc")/"php/#{version_major_minor}/php.ini",
          "php_dir"  => pear_path,
          "doc_dir"  => pear_path/"doc",
          "ext_dir"  => pecl_path/php_basename,
          "bin_dir"  => context_path("opt_prefix")/"bin",
          "data_dir" => pear_path/"data",
          "cfg_dir"  => pear_path/"cfg",
          "www_dir"  => pear_path/"htdocs",
          "man_dir"  => HOMEBREW_PREFIX/"share/man",
          "test_dir" => pear_path/"test",
          "php_bin"  => context_path("opt_prefix")/"bin/php",
        }.each do |key, value|
          value.mkpath if /(?<!bin|man)_dir$/.match?(key)
          run_command context_path("bin")/"pear", "config-set", key, value, "system"
        end
        run_command context_path("bin")/"pear", "update-channels"
        return if context_name == "php"

        ext_config_path = context_path("etc")/"php/#{version_major_minor}/conf.d/ext-opcache.ini"
        if ext_config_path.exist?
          ext_config_path.write ext_config_path.read.gsub(/zend_extension=.*$/,
                                                          "zend_extension=#{php_ext_dir}/opcache.so")
        else
          ext_config_path.write <<~INI
            [opcache]
            zend_extension="#{php_ext_dir}/opcache.so"
          INI
        end
      end

      sig { void }
      def run_bootstrap_cpython
        formula = @context
        raise ArgumentError, "CPython bootstrap requires a formula" unless formula.is_a?(Formula)

        ENV.delete("PYTHONPATH")
        version_string = context_version
        raise ArgumentError, "CPython bootstrap requires a version" if version_string.nil?

        version_major_minor = Version.new(version_string).major_minor.to_s
        require "language/python"
        site_packages = Language::Python.homebrew_site_packages(context_path("bin")/"python#{version_major_minor}")
        lib_cellar = if Homebrew::SimulateSystem.simulating_or_running_on_macos?
          context_path("frameworks")/"Python.framework/Versions/#{version_major_minor}/lib/python#{version_major_minor}"
        else
          context_path("lib")/"python#{version_major_minor}"
        end
        site_packages_cellar = lib_cellar/"site-packages"
        site_packages.mkpath
        site_packages_cellar.unlink if site_packages_cellar.exist?
        site_packages_cellar.parent.install_symlink site_packages
        FileUtils.rm_r Dir[site_packages/"sitecustomize.py[co]"], force: true
        %w[setuptools distribute pip wheel].each do |package|
          FileUtils.rm_r Dir[site_packages/"#{package}[-_.][0-9]*", site_packages/package], force: true
        end

        python = context_path("bin")/"python#{version_major_minor}"
        run_command python, "-Im", "ensurepip"
        bundled = lib_cellar/"ensurepip/_bundled"
        setuptools = formula.resource("setuptools")
        pip = formula.resource("pip")
        wheel = formula.resource("wheel")
        raise ArgumentError, "CPython bootstrap resources are missing" if setuptools.nil? || pip.nil? || wheel.nil?

        run_command python, "-Im", "pip", "install", "-v", "--no-deps", "--no-index", "--upgrade", "--isolated",
                    "--target=#{site_packages}",
                    bundled/"setuptools-#{setuptools.version}-py3-none-any.whl",
                    bundled/"pip-#{pip.version}-py3-none-any.whl",
                    context_path("libexec")/"wheel-#{wheel.version}-py3-none-any.whl"
        FileUtils.mv (site_packages/"bin").children, context_path("bin")
        (site_packages/"bin").rmdir
        FileUtils.rm_r context_path("bin").glob("pip{,3}"), force: true
        FileUtils.mv context_path("bin")/"wheel", context_path("bin")/"wheel#{version_major_minor}"
        {
          "pip"    => "pip#{version_major_minor}",
          "pip3"   => "pip#{version_major_minor}",
          "wheel"  => "wheel#{version_major_minor}",
          "wheel3" => "wheel#{version_major_minor}",
        }.each do |short_name, long_name|
          (context_path("libexec")/"bin").install_symlink (context_path("bin")/long_name).realpath => short_name
        end
        (HOMEBREW_PREFIX/"bin").install_symlink [context_path("bin")/"wheel#{version_major_minor}",
                                                 context_path("bin")/"pip#{version_major_minor}"]
        make_cpython_venv_activation_scripts_writable(lib_cellar)
        return if version_major_minor != "3.9"

        include_dirs = [HOMEBREW_PREFIX/"include", Utils::Path.formula_opt_prefix("openssl@3")/"include",
                        Utils::Path.formula_opt_prefix("sqlite")/"include"]
        library_dirs = [HOMEBREW_PREFIX/"lib", Utils::Path.formula_opt_prefix("openssl@3")/"lib",
                        Utils::Path.formula_opt_prefix("sqlite")/"lib"]
        (lib_cellar/"distutils/distutils.cfg").atomic_write <<~INI
          [install]
          prefix=#{HOMEBREW_PREFIX}
          [build_ext]
          include_dirs=#{include_dirs.join(":")}
          library_dirs=#{library_dirs.join(":")}
        INI
        framework_compat = site_packages/"setuptools/_distutils/command/_framework_compat.py"
        framework_compat.write framework_compat.read.gsub(/^(\s+homebrew_prefix\s+=\s+).*/, "\\1'#{HOMEBREW_PREFIX}'")
      end

      sig { params(lib_cellar: Pathname).void }
      def make_cpython_venv_activation_scripts_writable(lib_cellar)
        FileUtils.chmod "u+w", lib_cellar.glob("venv/scripts/**/*").select(&:file?)
      end

      sig { params(abi_version: String).void }
      def run_bootstrap_pypy(abi_version)
        formula = @context
        raise ArgumentError, "PyPy bootstrap requires a formula" unless formula.is_a?(Formula)

        pypy = context_path("bin")/"pypy#{abi_version}"
        %w[_sqlite3 _curses syslog gdbm _tkinter].each do |module_name|
          @command.run(pypy, args: ["-c", "import #{module_name}"], print_stdout: false, print_stderr: false)
        end
        site_packages = HOMEBREW_PREFIX/"lib/pypy#{abi_version}/site-packages"
        libexec_site_packages = context_path("libexec")/"lib/pypy#{abi_version}/site-packages"
        scripts_folder = HOMEBREW_PREFIX/"share/pypy#{abi_version}"
        site_packages.mkpath
        FileUtils.touch site_packages/".keepme"
        FileUtils.rm_rf libexec_site_packages
        libexec_site_packages.parent.install_symlink site_packages
        if abi_version == "3.9"
          if scripts_folder.symlink?
            scripts_folder.unlink
            scripts_folder.install_symlink context_path("pkgshare").children
          end
          unless (context_path("libexec")/"bin").exist?
            context_path("libexec").install_symlink scripts_folder => "bin"
          end
        end
        scripts_folder.mkpath
        (libexec_site_packages.parent/"distutils/distutils.cfg").atomic_write <<~INI
          [install]
          install-scripts=#{scripts_folder}
        INI
        %w[setuptools pip].each do |package|
          resource = formula.resource(package)
          raise ArgumentError, "PyPy bootstrap resource #{package} is missing" if resource.nil?

          resource.stage do
            run_command pypy, "-s", "setup.py", "--no-user-cfg", "install", "--force", "--verbose"
          end
        end
        context_path("bin").install_symlink scripts_folder/"pip#{abi_version}" => "pip_pypy#{abi_version}"
        prefix_links = [context_path("bin")/"pip_pypy#{abi_version}"]
        if formula == Formula["pypy3"]
          context_path("bin").install_symlink "pip_pypy#{abi_version}" => "pip_pypy3"
          prefix_links << (context_path("bin")/"pip_pypy3")
        end
        (HOMEBREW_PREFIX/"bin").install_symlink prefix_links
      end
    end
  end
end
