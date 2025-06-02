# frozen_string_literal: true

require_relative "path_scanner"

module Bootsnap
  module LoadPathCache
    class Path
      # A path is considered 'stable' if it is part of a Gem.path or the ruby
      # distribution. When adding or removing files in these paths, the cache
      # must be cleared before the change will be noticed.
      def stable?
        stability == STABLE
      end

      # A path is considered volatile if it doesn't live under a Gem.path or
      # the ruby distribution root. These paths are scanned for new additions
      # more frequently.
      def volatile?
        stability == VOLATILE
      end

      attr_reader(:path)

      def initialize(path, real: false)
        @path = path.to_s.freeze
        @real = real
      end

      def to_realpath
        return self if @real

        realpath = begin
          File.realpath(path)
        rescue Errno::ENOENT
          return self
        end

        if realpath == path
          @real = true
          self
        else
          Path.new(realpath, real: true)
        end
      end

      # True if the path exists, but represents a non-directory object
      def non_directory?
        !File.stat(path).directory?
      rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EINVAL
        false
      end

      def relative?
        !path.start_with?(SLASH)
      end

      # Return a list of all the requirable files and all of the subdirectories
      # of this +Path+.
      def entries_and_dirs(store)
        if stable?
          # the cached_mtime field is unused for 'stable' paths, but is
          # set to zero anyway, just in case we change the stability heuristics.
          _, entries, dirs = store.get(expanded_path)
          return [entries, dirs] if entries # cache hit

          entries, dirs = scan!
          store.set(expanded_path, [0, entries, dirs])
          return [entries, dirs]
        end

        cached_mtime, entries, dirs = store.get(expanded_path)

        current_mtime = latest_mtime(expanded_path, dirs || [])
        return [[], []]        if current_mtime == -1 # path does not exist
        return [entries, dirs] if cached_mtime == current_mtime

        entries, dirs = scan!
        store.set(expanded_path, [current_mtime, entries, dirs])
        [entries, dirs]
      end

      def expanded_path
        if @real
          path
        else
          @expanded_path ||= File.expand_path(path).freeze
        end
      end

      private

      def scan! # (expensive) returns [entries, dirs]
        PathScanner.call(expanded_path)
      end

      # last time a directory was modified in this subtree. +dirs+ should be a
      # list of relative paths to directories under +path+. e.g. for /a/b and
      # /a/b/c, pass ('/a/b', ['c'])
      def latest_mtime(path, dirs)
        max = -1
        ["", *dirs].each do |dir|
          curr = begin
            File.mtime("#{path}/#{dir}").to_i
                 rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EINVAL
                   -1
          end
          max = curr if curr > max
        end
        max
      end

      # a Path can be either stable of volatile, depending on how frequently we
      # expect its contents may change. Stable paths aren't rescanned nearly as
      # often.
      STABLE   = :stable
      VOLATILE = :volatile

      # Built-in ruby lib stuff doesn't change, but things can occasionally be
      # installed into sitedir, which generally lives under rubylibdir.
      RUBY_LIBDIR  = RbConfig::CONFIG["rubylibdir"]
      RUBY_SITEDIR = RbConfig::CONFIG["sitedir"]

      def stability
        @stability ||= if Gem.path.detect { |p| expanded_path.start_with?(p.to_s) }
          STABLE
        elsif Bootsnap.bundler? && expanded_path.start_with?(Bundler.bundle_path.to_s)
          STABLE
        elsif expanded_path.start_with?(RUBY_LIBDIR) && !expanded_path.start_with?(RUBY_SITEDIR)
          STABLE
        else
          VOLATILE
        end
      end
    end
  end
end
