# typed: strict
# frozen_string_literal: true

require "utils/formatter"

module DiskUsageExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  # Errors that `Find.find` also skips.
  SKIPPABLE_PATH_ERRORS = [
    Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL
  ].freeze
  private_constant :SKIPPABLE_PATH_ERRORS

  sig { returns(Integer) }
  def disk_usage
    @disk_usage ||= T.let(nil, T.nilable(Integer))
    return @disk_usage unless @disk_usage.nil?

    @file_count, @disk_usage = compute_disk_usage
    @disk_usage
  end

  sig { returns(Integer) }
  def file_count
    @file_count ||= T.let(nil, T.nilable(Integer))
    return @file_count unless @file_count.nil?

    @file_count, @disk_usage = compute_disk_usage
    @file_count
  end

  sig { returns(String) }
  def abv
    out = +""
    out << "#{Formatter.number_readable(file_count)} files, " if file_count > 1
    out << Formatter.disk_usage_readable(disk_usage).to_s
    out.freeze
  end

  private

  sig { returns([Integer, Integer]) }
  def compute_disk_usage
    if symlink? && !exist?
      file_count = 1
      disk_usage = 0
      return [file_count, disk_usage]
    end

    path = if symlink?
      Utils::Path.resolved_path(Pathname(to_path))
    else
      self
    end

    if path.directory?
      scanned_files = Set.new
      file_count = 0
      disk_usage = 0
      # Walk path strings rather than `Pathname#find`, which builds a `Pathname`
      # and makes `Find.find` `lstat` each entry before we `lstat` it again.
      entries = [path.to_s]
      while (entry = entries.pop)
        begin
          # use File.lstat instead of File.stat to get info of symlink itself.
          stat = File.lstat(entry)
        rescue *SKIPPABLE_PATH_ERRORS
          # Skip entries that vanished or can't be read.
          next
        end
        if stat.directory? || (stat.symlink? && File.directory?(entry))
          disk_usage += stat.size
        else
          file_count += 1 if File.basename(entry) != ".DS_Store"
          # count hardlinks only once.
          disk_usage += stat.size if scanned_files.add?([stat.dev, stat.ino])
        end
        next unless stat.directory?

        begin
          Dir.children(entry, encoding: entry.encoding).each do |child|
            entries << File.join(entry, child)
          end
        rescue *SKIPPABLE_PATH_ERRORS
          # Skip directories that can't be listed.
          nil
        end
      end
    else
      file_count = 1
      disk_usage = path.lstat.size
    end

    [file_count, disk_usage]
  end
end
