# typed: strict
# frozen_string_literal: true

require "system_command"

require "utils"
require "utils/output"

module Utils
  # Helpers for Homebrew path handling and package path validation.
  module Path
    extend Utils::Output::Mixin

    @install_info_executable = T.let(nil, T.nilable(String))

    # Path helpers available as private methods when this module is included.
    module Helpers
      extend T::Helpers

      requires_ancestor { Kernel }

      sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String)).returns(T::Boolean) }
      def child_of?(parent, child)
        parent_pathname = Pathname(parent).expand_path
        child_pathname = Pathname(child).expand_path
        child_pathname.ascend { |p| return true if p == parent_pathname }
        false
      end

      sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String), message: String).void }
      def ensure_child_of!(parent, child, message:)
        return if child_of?(resolve_symlinks(parent), resolve_symlinks(child))

        raise message
      rescue SystemCallError
        # Fail closed: an unresolvable symlink leaves containment unproven.
        raise message
      end

      sig {
        params(
          path:        Pathname,
          pattern:     T.any(Pathname, String, Regexp),
          replacement: T.any(Pathname, String),
          _block:      T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(Pathname)),
        ).void
      }
      def cp_path_sub(path, pattern, replacement, &_block)
        raise "#{path} does not exist" unless path.exist?

        pattern = pattern.to_s if pattern.is_a?(Pathname)
        replacement = replacement.to_s if replacement.is_a?(Pathname)
        dst = path.sub(pattern, replacement)

        raise "#{path} is the same file as #{dst}" if path == dst

        if path.directory?
          dst.mkpath
        else
          dst.dirname.mkpath
          dst = yield(path, dst) if block_given?
          FileUtils.cp(path, dst)
        end
      end

      sig { params(path: Pathname).returns(T::Boolean) }
      def rmdir_if_possible(path)
        path.rmdir
        true
      rescue Errno::ENOTEMPTY
        if (ds_store = path/".DS_Store").exist? && path.children.one?
          ds_store.unlink
          retry
        else
          false
        end
      rescue Errno::EACCES, Errno::ENOENT, Errno::EBUSY, Errno::EPERM
        false
      end

      sig { params(path: Pathname).returns(T::Boolean) }
      def text_executable?(path)
        /\A#!\s*\S+/.match?(path.open("r") { |file| file.read(1024) })
      end

      sig { params(path: Pathname).returns(Pathname) }
      def resolved_path(path)
        path.symlink? ? path.dirname.join(path.readlink) : path
      end

      sig { params(path: Pathname).returns(T::Boolean) }
      def resolved_path_exists?(path)
        link = path.readlink
      rescue ArgumentError
        false
      else
        path.dirname.join(link).exist?
      end

      sig { params(path: T.any(Pathname, String), _block: T.proc.void).void }
      def ensure_writable(path, &_block)
        path = Pathname(path)
        saved_perms = nil
        unless path.writable?
          saved_perms = path.stat.mode
          FileUtils.chmod "u+rw", path.to_path
        end
        yield
      ensure
        path.chmod saved_perms if saved_perms
      end

      # `Pathname#relative_path_from` without its `cleanpath` calls for clean absolute paths.
      sig { params(path: Pathname, base: Pathname).returns(Pathname) }
      def relative_path_from(path, base)
        path_string = path.to_s
        base_string = base.to_s
        if File::FNM_SYSCASE.zero? && clean_absolute_path?(path_string) && clean_absolute_path?(base_string)
          base_prefix = "#{base_string}/"
          return Pathname(path_string.delete_prefix(base_prefix)) if path_string.start_with?(base_prefix)

          path_names = path_string.split("/").drop(1)
          base_names = base_string.split("/").drop(1)
          common = 0
          common += 1 while common < path_names.length && path_names[common] == base_names[common]
          names = Array.new(base_names.length - common, "..") + path_names.drop(common)
          return Pathname(names.empty? ? "." : File.join(*names))
        end

        path.relative_path_from(base)
      end

      private

      sig { params(path: String).returns(T::Boolean) }
      def clean_absolute_path?(path)
        path.start_with?("/") && path.exclude?("//") && path.exclude?("/./") && path.exclude?("/../") &&
          !path.end_with?("/.", "/..") && (path == "/" || !path.end_with?("/"))
      end

      # `child_of?` is lexical, so resolve the deepest existing component first.
      # Stop at a symlink too: `exist?` follows one, hiding a dangling link.
      sig { params(path: T.any(Pathname, String)).returns(Pathname) }
      def resolve_symlinks(path)
        pathname = Pathname(path).expand_path
        existing = pathname
        existing = existing.parent until existing.exist? || existing.symlink? || existing.root?
        (existing.realpath/pathname.relative_path_from(existing)).cleanpath
      end
    end

    include Helpers
    extend Helpers

    private :child_of?, :ensure_child_of!, :cp_path_sub, :rmdir_if_possible, :text_executable?, :resolved_path,
            :resolved_path_exists?, :ensure_writable, :relative_path_from

    class << self
      public :child_of?, :ensure_child_of!, :cp_path_sub, :rmdir_if_possible, :text_executable?, :resolved_path,
             :resolved_path_exists?, :ensure_writable, :relative_path_from
    end

    sig { params(path: Pathname, verbose: T::Boolean).void }
    def self.install_info(path, verbose: false)
      SystemCommand.quiet_system(install_info_executable, "--quiet", path.to_s, (path.dirname/"dir").to_s)
      puts "info #{path}" if verbose
    end

    sig { params(path: Pathname, verbose: T::Boolean).void }
    def self.uninstall_info(path, verbose: false)
      SystemCommand.quiet_system(install_info_executable, "--delete", "--quiet", path.to_s, (path.dirname/"dir").to_s)
      puts "uninfo #{path}" if verbose
    end

    sig { returns(T.nilable(String)) }
    private_class_method def self.install_info_executable
      @install_info_executable ||= if File.executable?("/usr/bin/install-info")
        "/usr/bin/install-info"
      elsif (texinfo_formula = Formula["texinfo"]).any_version_installed?
        (texinfo_formula.opt_bin/"install-info").to_s
      end
    end

    # Public Formula and Cask DSL path helpers.
    module FormulaHelpers
      # The stable install path for a given formula name.
      #
      # @api public
      sig { params(formula_name: String).returns(Pathname) }
      def formula_opt_prefix(formula_name)
        HOMEBREW_PREFIX/"opt/#{Utils.name_from_full_name(formula_name)}"
      end

      # The `bin` directory under the stable install path for a given formula name.
      #
      # @api public
      sig { params(formula_name: String).returns(Pathname) }
      def formula_opt_bin(formula_name)
        formula_opt_prefix(formula_name)/"bin"
      end

      # The `lib` directory under the stable install path for a given formula name.
      #
      # @api public
      sig { params(formula_name: String).returns(Pathname) }
      def formula_opt_lib(formula_name)
        formula_opt_prefix(formula_name)/"lib"
      end

      # The `libexec` directory under the stable install path for a given formula name.
      #
      # @api public
      sig { params(formula_name: String).returns(Pathname) }
      def formula_opt_libexec(formula_name)
        formula_opt_prefix(formula_name)/"libexec"
      end

      # The `include` directory under the stable install path for a given formula name.
      #
      # @api public
      sig { params(formula_name: String).returns(Pathname) }
      def formula_opt_include(formula_name)
        formula_opt_prefix(formula_name)/"include"
      end

      # Whether any installed keg for one or more formula names has an install receipt.
      #
      # @api public
      sig { params(formula_names: T.any(String, T::Array[String])).returns(T::Boolean) }
      def formula_any_version_installed?(formula_names)
        Utils::Path.formula_installed_prefixes(formula_names).any? do |keg|
          (keg/"INSTALL_RECEIPT.json").file?
        end
      end
    end

    include FormulaHelpers
    extend FormulaHelpers

    # The installed prefix directories for one or more formula names.
    #
    # @api public
    sig { params(formula_names: T.any(String, T::Array[String])).returns(T::Array[Pathname]) }
    def self.formula_installed_prefixes(formula_names)
      Array(formula_names).map { |formula_name| HOMEBREW_CELLAR/Utils.name_from_full_name(formula_name) }
                          .select(&:directory?)
                          .uniq(&:realpath)
                          .flat_map(&:subdirs)
                          .sort_by(&:basename)
    end

    # The current `PATH` with a formula's stable `bin` directory prepended.
    #
    # @api public
    sig { params(formula_name: String, paths: PATH::Elements).returns(PATH) }
    def self.formula_opt_bin_path(formula_name, *paths)
      PATH.new(formula_opt_bin(formula_name), *paths, ENV.fetch("PATH"))
    end

    # An environment hash with `PATH` prepended by a formula's stable `bin` directory.
    #
    # @api public
    sig { params(formula_name: String, paths: PATH::Elements).returns(T::Hash[String, String]) }
    def self.formula_opt_bin_env(formula_name, *paths)
      { "PATH" => formula_opt_bin_path(formula_name, *paths).to_s }
    end

    T::Sig::WithoutRuntime.sig { params(_path: Pathname, _package_type: Symbol).returns(T::Boolean) }
    def self.loadable_package_path?(_path, _package_type)
      odeprecated "Utils::Path.loadable_package_path?", "explicit internal Formulary/CaskLoader.from_path calls"
      false
    end

    # Accept bare package names or user/tap/name references, never filesystem paths.
    T::Sig::WithoutRuntime.sig { params(name: T.anything).returns(T::Boolean) }
    def self.valid_package_name?(name)
      case name
      when String
        name.match?(HOMEBREW_PACKAGE_REFERENCE_REGEX) &&
          !name.split("/").intersect?(Utils::INVALID_PATH_COMPONENTS)
      else
        false
      end
    end

    # Resolve an audited source path to its registered tap file, including symlinked checkouts.
    # @api private
    sig { params(path: Pathname, package_type: Symbol).returns(T.nilable(Pathname)) }
    def self.tap_package_path(path, package_type)
      return unless path.file?

      require "api/env"

      path = path.expand_path
      tap = Tap.from_path(path)
      unless tap
        path = path.realpath
        tap = Tap.installed.find do |installed_tap|
          installed_tap.path.directory? && path.to_s.start_with?("#{installed_tap.path.realpath}/")
        end
        return unless tap
      end

      files = Homebrew::API.with_no_api_env do
        (package_type == :formula) ? tap.formula_files : tap.cask_files
      end
      # Tap caches file lists sorted by full path.
      return path if files.bsearch { |file| file.to_s >= path.to_s } == path

      candidate = tap.path/path.realpath.relative_path_from(tap.path.realpath)
      candidate if files.bsearch { |file| file.to_s >= candidate.to_s } == candidate
    end
  end
end
