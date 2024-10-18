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

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      path.find(ignore_error: false) do |src|
        next if src == path

        dst = unpack_dir/src.relative_path_from(path)

        if dst.directory? && !dst.symlink?
          # Output same error as `cp` when trying to copy over an existing directory
          raise "#{dst}: Is a directory" if !src.directory? || src.symlink?

          begin
            # Fix group caused by unpacking into tmp dir. Try to copy valid group over
            FileUtils.chown(nil, src.lstat.gid == "wheel" ? dst.parent.lstat.gid : src_gid, dst)
            FileUtils.chown(src.lstat.uid, nil, dst)
          rescue Errno::EPERM, Errno::EACCES
            # Keep behavior similar to `cp -p` which does not error on user/group ID changes
          end
          FileUtils.chmod(src.lstat.mode, dst)
          FileUtils.touch(dst, mtime: src.mtime, nocreate: true)
        else
          FileUtils.mv(src, dst)
          begin
            # Fix group caused by unpacking into tmp dir
            FileUtils.chown_R(nil, dst.parent.lstat.gid, dst) if dst.lstat.gid == "wheel"
          rescue Errno::EPERM, Errno::EACCES
            # Keep behavior similar to `cp -p` which does not error on user/group ID changes
          end
          Find.prune
        end
      end
    end
  end
end
