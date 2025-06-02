# frozen_string_literal: true

module Bundler
  module Plugin
    class Installer
      class Git < Bundler::Source::Git
        def cache_path
          @cache_path ||= begin
            git_scope = "#{base_name}-#{uri_hash}"

            Plugin.cache.join("bundler", "git", git_scope)
          end
        end

        def install_path
          @install_path ||= begin
            git_scope = "#{base_name}-#{shortref_for_path(revision)}"

            Plugin.root.join("bundler", "gems", git_scope)
          end
        end

        def root
          Plugin.root
        end

        def generate_bin(spec, disable_extensions = false)
          # Need to find a way without code duplication
          # For now, we can ignore this
        end
      end
    end
  end
end
