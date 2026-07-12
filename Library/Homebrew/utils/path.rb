# typed: strict
# frozen_string_literal: true

require "utils"

module Utils
  # Helpers for Homebrew path handling and package path validation.
  module Path
    sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String)).returns(T::Boolean) }
    def self.child_of?(parent, child)
      parent_pathname = Pathname(parent).expand_path
      child_pathname = Pathname(child).expand_path
      child_pathname.ascend { |p| return true if p == parent_pathname }
      false
    end

    sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String), message: String).void }
    def self.ensure_child_of!(parent, child, message:)
      return if child_of?(parent, child)

      raise message
    end

    # The stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def self.formula_opt_prefix(formula_name)
      HOMEBREW_PREFIX/"opt/#{Utils.name_from_full_name(formula_name)}"
    end

    # The stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def formula_opt_prefix(formula_name)
      Utils::Path.formula_opt_prefix(formula_name)
    end

    # The `bin` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def self.formula_opt_bin(formula_name)
      formula_opt_prefix(formula_name)/"bin"
    end

    # The `bin` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def formula_opt_bin(formula_name)
      Utils::Path.formula_opt_bin(formula_name)
    end

    # The `lib` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def self.formula_opt_lib(formula_name)
      formula_opt_prefix(formula_name)/"lib"
    end

    # The `lib` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def formula_opt_lib(formula_name)
      Utils::Path.formula_opt_lib(formula_name)
    end

    # The `libexec` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def self.formula_opt_libexec(formula_name)
      formula_opt_prefix(formula_name)/"libexec"
    end

    # The `libexec` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def formula_opt_libexec(formula_name)
      Utils::Path.formula_opt_libexec(formula_name)
    end

    # The `include` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def self.formula_opt_include(formula_name)
      formula_opt_prefix(formula_name)/"include"
    end

    # The `include` directory under the stable install path for a given formula name.
    #
    # @api public
    sig { params(formula_name: String).returns(Pathname) }
    def formula_opt_include(formula_name)
      Utils::Path.formula_opt_include(formula_name)
    end

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

    # Whether any installed keg for one or more formula names has an install receipt.
    #
    # @api public
    sig { params(formula_names: T.any(String, T::Array[String])).returns(T::Boolean) }
    def self.formula_any_version_installed?(formula_names)
      formula_installed_prefixes(formula_names).any? { |keg| (keg/"INSTALL_RECEIPT.json").file? }
    end

    # Whether any installed keg for one or more formula names has an install receipt.
    #
    # @api public
    sig { params(formula_names: T.any(String, T::Array[String])).returns(T::Boolean) }
    def formula_any_version_installed?(formula_names)
      Utils::Path.formula_any_version_installed?(formula_names)
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
