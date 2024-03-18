# typed: true
# frozen_string_literal: true

module Language
  # Helper functions for Python formulae.
  #
  # @api public
  module Python
    sig { params(python: T.any(String, Pathname)).returns(T.nilable(Version)) }
    def self.major_minor_version(python)
      version = `#{python} --version 2>&1`.chomp[/(\d\.\d+)/, 1]
      return unless version

      Version.new(version)
    end

    sig { params(python: T.any(String, Pathname)).returns(Pathname) }
    def self.homebrew_site_packages(python = "python3.7")
      HOMEBREW_PREFIX/site_packages(python)
    end

    sig { params(python: T.any(String, Pathname)).returns(String) }
    def self.site_packages(python = "python3.7")
      if (python == "pypy") || (python == "pypy3")
        "site-packages"
      else
        "lib/python#{major_minor_version python}/site-packages"
      end
    end

    def self.each_python(build, &block)
      original_pythonpath = ENV.fetch("PYTHONPATH", nil)
      pythons = { "python@3" => "python3",
                  "pypy"     => "pypy",
                  "pypy3"    => "pypy3" }
      pythons.each do |python_formula, python|
        python_formula = Formulary.factory(python_formula)
        next if build.without? python_formula.to_s

        version = major_minor_version python
        ENV["PYTHONPATH"] = if python_formula.latest_version_installed?
          nil
        else
          homebrew_site_packages(python).to_s
        end
        block&.call python, version
      end
      ENV["PYTHONPATH"] = original_pythonpath
    end

    def self.reads_brewed_pth_files?(python)
      return false unless homebrew_site_packages(python).directory?
      return false unless homebrew_site_packages(python).writable_real?

      probe_file = homebrew_site_packages(python)/"homebrew-pth-probe.pth"
      begin
        probe_file.atomic_write("import site; site.homebrew_was_here = True")
        with_homebrew_path { quiet_system python, "-c", "import site; assert(site.homebrew_was_here)" }
      ensure
        probe_file.unlink if probe_file.exist?
      end
    end

    def self.user_site_packages(python)
      Pathname.new(`#{python} -c "import site; print(site.getusersitepackages())"`.chomp)
    end

    def self.in_sys_path?(python, path)
      script = <<~PYTHON
        import os, sys
        [os.path.realpath(p) for p in sys.path].index(os.path.realpath("#{path}"))
      PYTHON
      quiet_system python, "-c", script
    end

    sig { params(prefix: Pathname, python: T.any(String, Pathname)).returns(T::Array[String]) }
    def self.setup_install_args(prefix, python = "python3")
      shim = <<~PYTHON
        import setuptools, tokenize
        __file__ = 'setup.py'
        exec(compile(getattr(tokenize, 'open', open)(__file__).read()
          .replace('\\r\\n', '\\n'), __file__, 'exec'))
      PYTHON
      %W[
        -c
        #{shim}
        --no-user-cfg
        install
        --prefix=#{prefix}
        --install-scripts=#{prefix}/bin
        --install-lib=#{prefix/site_packages(python)}
        --single-version-externally-managed
        --record=installed.txt
      ]
    end

    # Mixin module for {Formula} adding shebang rewrite features.
    module Shebang
      module_function

      # A regex to match potential shebang permutations.
      PYTHON_SHEBANG_REGEX = %r{^#! ?/usr/bin/(?:env )?python(?:[23](?:\.\d{1,2})?)?( |$)}

      # The length of the longest shebang matching `SHEBANG_REGEX`.
      PYTHON_SHEBANG_MAX_LENGTH = "#! /usr/bin/env pythonx.yyy ".length

      # @private
      sig { params(python_path: T.any(String, Pathname)).returns(Utils::Shebang::RewriteInfo) }
      def python_shebang_rewrite_info(python_path)
        Utils::Shebang::RewriteInfo.new(
          PYTHON_SHEBANG_REGEX,
          PYTHON_SHEBANG_MAX_LENGTH,
          "#{python_path}\\1",
        )
      end

      sig { params(formula: Formula, use_python_from_path: T::Boolean).returns(Utils::Shebang::RewriteInfo) }
      def detected_python_shebang(formula = T.cast(self, Formula), use_python_from_path: false)
        python_path = if use_python_from_path
          "/usr/bin/env python3"
        else
          python_deps = formula.deps.map(&:name).grep(/^python(@.+)?$/)
          raise ShebangDetectionError.new("Python", "formula does not depend on Python") if python_deps.empty?
          if python_deps.length > 1
            raise ShebangDetectionError.new("Python", "formula has multiple Python dependencies")
          end

          python_dep = python_deps.first
          Formula[python_dep].opt_bin/python_dep.sub("@", "")
        end

        python_shebang_rewrite_info(python_path)
      end
    end

    # Mixin module for {Formula} adding virtualenv support features.
    module Virtualenv
      # Instantiates, creates, and yields a {Virtualenv} object for use from
      # {Formula#install}, which provides helper methods for instantiating and
      # installing packages into a Python virtualenv.
      #
      # @param venv_root [Pathname, String] the path to the root of the virtualenv
      #   (often `libexec/"venv"`)
      # @param python [String, Pathname] which interpreter to use (e.g. "python3"
      #   or "python3.x")
      # @param formula [Formula] the active {Formula}
      # @return [Virtualenv] a {Virtualenv} instance
      sig {
        params(
          venv_root:            T.any(String, Pathname),
          python:               T.any(String, Pathname),
          formula:              Formula,
          system_site_packages: T::Boolean,
          without_pip:          T::Boolean,
        ).returns(Virtualenv)
      }
      def virtualenv_create(venv_root, python = "python", formula = T.cast(self, Formula),
                            system_site_packages: true, without_pip: true)
        # Limit deprecation to 3.12+ for now (or if we can't determine the version).
        # Some used this argument for setuptools, which we no longer bundle since 3.12.
        unless without_pip
          python_version = Language::Python.major_minor_version(python)
          if python_version.nil? || python_version.null? || python_version >= "3.12"
            raise ArgumentError, "virtualenv_create's without_pip is deprecated starting with Python 3.12"
          end
        end

        ENV.refurbish_args
        venv = Virtualenv.new formula, venv_root, python
        venv.create(system_site_packages:, without_pip:)

        # Find any Python bindings provided by recursive dependencies
        formula_deps = formula.recursive_dependencies
        pth_contents = formula_deps.filter_map do |d|
          next if d.build? || d.test?
          # Do not add the main site-package provided by the brewed
          # Python formula, to keep the virtual-env's site-package pristine
          next if python_names.include? d.name

          dep_site_packages = Formula[d.name].opt_prefix/Language::Python.site_packages(python)
          next unless dep_site_packages.exist?

          "import site; site.addsitedir('#{dep_site_packages}')\n"
        end
        (venv.site_packages/"homebrew_deps.pth").write pth_contents.join unless pth_contents.empty?

        venv
      end

      # Returns true if a formula option for the specified python is currently
      # active or if the specified python is required by the formula. Valid
      # inputs are "python", "python2", and :python3. Note that
      # "with-python", "without-python", "with-python@2", and "without-python@2"
      # formula options are handled correctly even if not associated with any
      # corresponding depends_on statement.
      #
      # @api private
      sig { params(python: String).returns(T::Boolean) }
      def needs_python?(python)
        return true if build.with?(python)

        (requirements.to_a | deps).any? { |r| r.name.split("/").last == python && r.required? }
      end

      # Helper method for the common case of installing a Python application.
      # Creates a virtualenv in `libexec`, installs all `resource`s defined
      # on the formula, and then installs the formula. An options hash may be
      # passed (e.g. `:using => "python"`) to override the default, guessed
      # formula preference for python or python@x.y, or to resolve an ambiguous
      # case where it's not clear whether python or python@x.y should be the
      # default guess.
      sig {
        params(
          using:                T.nilable(String),
          system_site_packages: T::Boolean,
          without_pip:          T::Boolean,
          link_manpages:        T::Boolean,
        ).returns(Virtualenv)
      }
      def virtualenv_install_with_resources(using: nil, system_site_packages: true, without_pip: true,
                                            link_manpages: false)
        python = using
        if python.nil?
          wanted = python_names.select { |py| needs_python?(py) }
          raise FormulaUnknownPythonError, self if wanted.empty?
          raise FormulaAmbiguousPythonError, self if wanted.size > 1

          python = T.must(wanted.first)
          python = "python3" if python == "python"
        end
        venv = virtualenv_create(libexec, python.delete("@"), system_site_packages:,
                                                              without_pip:)
        venv.pip_install resources
        venv.pip_install_and_link(T.must(buildpath), link_manpages:)
        venv
      end

      sig { returns(T::Array[String]) }
      def python_names
        %w[python python3 pypy pypy3] + Formula.names.select { |name| name.start_with? "python@" }
      end

      # Convenience wrapper for creating and installing packages into Python
      # virtualenvs.
      class Virtualenv
        # Initializes a Virtualenv instance. This does not create the virtualenv
        # on disk; {#create} does that.
        #
        # @param formula [Formula] the active {Formula}
        # @param venv_root [Pathname, String] the path to the root of the
        #   virtualenv
        # @param python [String, Pathname] which interpreter to use, e.g.
        #   "python" or "python2"
        sig { params(formula: Formula, venv_root: T.any(String, Pathname), python: T.any(String, Pathname)).void }
        def initialize(formula, venv_root, python)
          @formula = formula
          @venv_root = Pathname.new(venv_root)
          @python = python
        end

        sig { returns(Pathname) }
        def root
          @venv_root
        end

        sig { returns(Pathname) }
        def site_packages
          @venv_root/Language::Python.site_packages(@python)
        end

        # Obtains a copy of the virtualenv library and creates a new virtualenv on disk.
        #
        # @return [void]
        sig { params(system_site_packages: T::Boolean, without_pip: T::Boolean).void }
        def create(system_site_packages: true, without_pip: true)
          return if (@venv_root/"bin/python").exist?

          args = ["-m", "venv"]
          args << "--system-site-packages" if system_site_packages
          args << "--without-pip" if without_pip
          @formula.system @python, *args, @venv_root

          # Robustify symlinks to survive python patch upgrades
          @venv_root.find do |f|
            next unless f.symlink?
            next unless (rp = f.realpath.to_s).start_with? HOMEBREW_CELLAR

            version = rp.match %r{^#{HOMEBREW_CELLAR}/python@(.*?)/}o
            version = "@#{version.captures.first}" unless version.nil?

            new_target = rp.sub %r{#{HOMEBREW_CELLAR}/python#{version}/[^/]+}, Formula["python#{version}"].opt_prefix
            f.unlink
            f.make_symlink new_target
          end

          Pathname.glob(@venv_root/"lib/python*/orig-prefix.txt").each do |prefix_file|
            prefix_path = prefix_file.read

            version = prefix_path.match %r{^#{HOMEBREW_CELLAR}/python@(.*?)/}o
            version = "@#{version.captures.first}" unless version.nil?

            prefix_path.sub! %r{^#{HOMEBREW_CELLAR}/python#{version}/[^/]+}, Formula["python#{version}"].opt_prefix
            prefix_file.atomic_write prefix_path
          end

          # Remove unnecessary activate scripts
          (@venv_root/"bin").glob("[Aa]ctivate*").map(&:unlink)
        end

        # Installs packages represented by `targets` into the virtualenv.
        #
        # @param targets [String, Pathname, Resource,
        #   Array<String, Pathname, Resource>] (A) token(s) passed to `pip`
        #   representing the object to be installed. This can be a directory
        #   containing a setup.py, a {Resource} which will be staged and
        #   installed, or a package identifier to be fetched from PyPI.
        #   Multiline strings are allowed and treated as though they represent
        #   the contents of a `requirements.txt`.
        # @return [void]
        sig {
          params(
            targets:         T.any(String, Pathname, Resource, T::Array[T.any(String, Pathname, Resource)]),
            build_isolation: T::Boolean,
          ).void
        }
        def pip_install(targets, build_isolation: true)
          targets = Array(targets)
          targets.each do |t|
            if t.is_a?(Resource)
              t.stage { do_install(Pathname.pwd, build_isolation:) }
            else
              t = t.lines.map(&:strip) if t.is_a?(String) && t.include?("\n")
              do_install(t, build_isolation:)
            end
          end
        end

        # Installs packages represented by `targets` into the virtualenv, but
        # unlike {#pip_install} also links new scripts to {Formula#bin}.
        #
        # @param (see #pip_install)
        # @return (see #pip_install)
        sig {
          params(
            targets:         T.any(String, Pathname, Resource, T::Array[T.any(String, Pathname, Resource)]),
            link_manpages:   T::Boolean,
            build_isolation: T::Boolean,
          ).void
        }
        def pip_install_and_link(targets, link_manpages: false, build_isolation: true)
          bin_before = Dir[@venv_root/"bin/*"].to_set
          man_before = Dir[@venv_root/"share/man/man*/*"].to_set if link_manpages

          pip_install(targets, build_isolation:)

          bin_after = Dir[@venv_root/"bin/*"].to_set
          bin_to_link = (bin_after - bin_before).to_a
          @formula.bin.install_symlink(bin_to_link)
          return unless link_manpages

          man_after = Dir[@venv_root/"share/man/man*/*"].to_set
          man_to_link = (man_after - man_before).to_a
          man_to_link.each do |manpage|
            (@formula.man/Pathname.new(manpage).dirname.basename).install_symlink manpage
          end
        end

        private

        sig {
          params(
            targets:         T.any(String, Pathname, T::Array[T.any(String, Pathname)]),
            build_isolation: T::Boolean,
          ).void
        }
        def do_install(targets, build_isolation: true)
          targets = Array(targets)
          args = @formula.std_pip_args(prefix: false, build_isolation:)
          @formula.system @python, "-m", "pip", "--python=#{@venv_root}/bin/python", "install", *args, *targets
        end
      end
    end
  end
end
