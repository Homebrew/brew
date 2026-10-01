# typed: strict
# frozen_string_literal: true

require "system_command"

require "utils"

module Utils
  # Helpers for Homebrew path handling and package path validation.
  module Path
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

      private

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
            :resolved_path_exists?, :ensure_writable

    class << self
      public :child_of?, :ensure_child_of!, :cp_path_sub, :rmdir_if_possible, :text_executable?, :resolved_path,
             :resolved_path_exists?, :ensure_writable
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

    sig { params(path: Pathname, package_type: Symbol).returns(T::Boolean) }
    def self.loadable_package_path?(path, package_type)
      return true unless Homebrew::EnvConfig.forbid_packages_from_paths?

      path_realpath = path.realpath.to_s
      path_string = path.to_s

      allowed_paths = [trusted_package_root("#{HOMEBREW_LIBRARY}/Taps/")]
      allowed_paths << if package_type == :formula
        trusted_package_root(HOMEBREW_CELLAR)
      else
        trusted_package_root(Cask::Caskroom.path)
      end

      # Casks can also be loaded from local JSON files, not just Ruby.
      package_extnames = (package_type == :cask) ? %w[.rb .json] : %w[.rb]
      return true if package_extnames.none? { |ext| path_realpath.end_with?(ext) || path_string.end_with?(ext) }

      # Compare path ancestry, not string prefixes, so `..` can't escape a trusted root.
      return true if allowed_paths.any? { |root| child_of?(root, path_realpath) }
      return true if allowed_paths.any? { |root| child_of?(root, path) }

      # Looks like a local path, Ruby file and not a tap.
      if path_string.include?("./") || path_string.end_with?(".rb") || path_string.count("/") != 2
        package_type_plural = Utils.pluralize(package_type.to_s, 2)
        path_realpath_if_different = " (#{path_realpath})" if path_realpath != path_string
        create_flag = " --cask" if package_type == :cask

        raise <<~WARNING
          Homebrew requires #{package_type_plural} to be in a tap, rejecting:
            #{path_string}#{path_realpath_if_different}

          To create a tap, run e.g.
            brew tap-new <user|org>/<repository>
          To create a #{package_type} in a tap run e.g.
            brew create#{create_flag} <url> --tap=<user|org>/<repository>
        WARNING
      else
        # Looks like a tap, let's quietly reject but not error.
        path_string.count("/") != 2
      end
    end

    sig { params(path: T.any(Pathname, String)).returns(String) }
    def self.trusted_package_root(path)
      Pathname(path).realpath.to_s
    rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
      Pathname(path).expand_path.to_s
    end
    private_class_method :trusted_package_root
  end
end
