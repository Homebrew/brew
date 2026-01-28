# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking directories.
  class Directory
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      []
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.directory?
    end

    sig {
      params(
        path:         T.any(String, Pathname),
        ref_type:     T.nilable(Symbol),
        ref:          T.nilable(String),
        merge_xattrs: T::Boolean,
        move:         T::Boolean,
      ).void
    }
    def initialize(path, ref_type: nil, ref: nil, merge_xattrs: false, move: false)
      super(path, ref_type:, ref:, merge_xattrs:)
      @move = move
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      move_to_dir(unpack_dir, verbose:) if @move
      path_children = path.children
      return if path_children.empty?

      system_command!("cp", args: ["-pR", *path_children, unpack_dir], verbose:)
    end

    # Move all files from source `path` to target `unpack_dir`. Any existing
    # subdirectories are not modified and only the contents are moved.
    #
    # @raise [RuntimeError] on unsupported `mv` operation, e.g. overwriting a file with a directory
    sig { params(unpack_dir: Pathname, verbose: T::Boolean).void }
    def move_to_dir(unpack_dir, verbose:)
      path.find do |src|
        next if src == path

        dst = unpack_dir/src.relative_path_from(path)
        if dst.exist?
          dst_real_dir = dst.directory? && !dst.symlink?
          src_real_dir = src.directory? && !src.symlink?
          # Avoid moving a directory over an existing non-directory and vice versa.
          # This outputs the same error message as GNU mv which is more readable than macOS mv.
          raise "mv: cannot overwrite non-directory '#{dst}' with directory '#{src}'" if src_real_dir && !dst_real_dir
          raise "mv: cannot overwrite directory '#{dst}' with non-directory '#{src}'" if !src_real_dir && dst_real_dir
          # Defer writing over existing directories. Handle this later on to copy attributes
          next if dst_real_dir

          FileUtils.rm(dst, verbose:)
        end

        FileUtils.mv(src, dst, verbose:)
        Find.prune
      end
    end
  end
end
