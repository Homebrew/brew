# typed: strict
# frozen_string_literal: true

module Utils
  module Path
    sig { params(parent: T.any(Pathname, String), child: T.any(Pathname, String)).returns(T::Boolean) }
    def self.child_of?(parent, child)
      parent_pathname = Pathname(parent).expand_path
      child_pathname = Pathname(child).expand_path
      child_pathname.ascend { |p| return true if p == parent_pathname }
      false
    end

    sig { params(path: Pathname, package_type: Symbol).returns(T::Boolean) }
    def self.loadable_package_path?(path, package_type)
      return true unless Homebrew::EnvConfig.forbid_packages_from_paths?

      path_realpath = path.realpath.to_s
      path_string = path.to_s

      allowed_paths = ["#{HOMEBREW_LIBRARY}/Taps/"]
      allowed_paths << if package_type == :formula
        "#{HOMEBREW_CELLAR}/"
      else
        "#{Cask::Caskroom.path}/"
      end

      return true if !path_realpath.end_with?(".rb") && !path_string.end_with?(".rb")
      return true if allowed_paths.any? { |path| path_realpath.start_with?(path) }
      return true if allowed_paths.any? { |path| path_string.start_with?(path) }

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
  end
end
