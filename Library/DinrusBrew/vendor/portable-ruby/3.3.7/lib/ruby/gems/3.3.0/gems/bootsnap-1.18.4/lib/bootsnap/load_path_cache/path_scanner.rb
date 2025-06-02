# frozen_string_literal: true

require_relative "../explicit_require"

module Bootsnap
  module LoadPathCache
    module PathScanner
      REQUIRABLE_EXTENSIONS = [DOT_RB] + DL_EXTENSIONS
      NORMALIZE_NATIVE_EXTENSIONS = !DL_EXTENSIONS.include?(LoadPathCache::DOT_SO)
      ALTERNATIVE_NATIVE_EXTENSIONS_PATTERN = /\.(o|bundle|dylib)\z/.freeze

      BUNDLE_PATH = if Bootsnap.bundler?
        (Bundler.bundle_path.cleanpath.to_s << LoadPathCache::SLASH).freeze
      else
        ""
      end

      @ignored_directories = %w(node_modules)

      class << self
        attr_accessor :ignored_directories

        def call(path)
          path = File.expand_path(path.to_s).freeze
          return [[], []] unless File.directory?(path)

          # If the bundle path is a descendent of this path, we do additional
          # checks to prevent recursing into the bundle path as we recurse
          # through this path. We don't want to scan the bundle path because
          # anything useful in it will be present on other load path items.
          #
          # This can happen if, for example, the user adds '.' to the load path,
          # and the bundle path is '.bundle'.
          contains_bundle_path = BUNDLE_PATH.start_with?(path)

          dirs = []
          requirables = []
          walk(path, nil) do |relative_path, absolute_path, is_directory|
            if is_directory
              dirs << os_path(relative_path)
              !contains_bundle_path || !absolute_path.start_with?(BUNDLE_PATH)
            elsif relative_path.end_with?(*REQUIRABLE_EXTENSIONS)
              requirables << os_path(relative_path)
            end
          end
          [requirables, dirs]
        end

        def walk(absolute_dir_path, relative_dir_path, &block)
          Dir.foreach(absolute_dir_path) do |name|
            next if name.start_with?(".")

            relative_path = relative_dir_path ? File.join(relative_dir_path, name) : name

            absolute_path = "#{absolute_dir_path}/#{name}"
            if File.directory?(absolute_path)
              next if ignored_directories.include?(name) || ignored_directories.include?(absolute_path)

              if yield relative_path, absolute_path, true
                walk(absolute_path, relative_path, &block)
              end
            else
              yield relative_path, absolute_path, false
            end
          end
        end

        if RUBY_VERSION >= "3.1"
          def os_path(path)
            path.freeze
          end
        else
          def os_path(path)
            path.force_encoding(Encoding::US_ASCII) if path.ascii_only?
            path.freeze
          end
        end
      end
    end
  end
end
