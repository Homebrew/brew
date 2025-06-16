# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module DiskUsageExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  sig { returns(Integer) }
  def disk_usage
    return @disk_usage if defined?(@disk_usage)

    compute_disk_usage
    @disk_usage
  end

  sig { returns(Integer) }
  def file_count
    return @file_count if defined?(@file_count)

    compute_disk_usage
    @file_count
  end

  sig { returns(String) }
  def abv
    out = +""
    compute_disk_usage
    out << "#{number_readable(@file_count)} files, " if @file_count > 1
    out << disk_usage_readable(@disk_usage).to_s
    out.freeze
  end

  private

  sig { void }
  def compute_disk_usage
    if symlink? && !exist?
      @file_count = 1
      @disk_usage = 0
      return
    end

    path = if symlink?
      resolved_path
    else
      self
    end

    if path.directory?
      scanned_files = Set.new
      @file_count = 0
      @disk_usage = 0
      path.find do |f|
        if f.directory?
          @disk_usage += f.lstat.size
        else
          @file_count += 1 if f.basename.to_s != ".DS_Store"
          # use Pathname#lstat instead of Pathname#stat to get info of symlink itself.
          stat = f.lstat
          file_id = [stat.dev, stat.ino]
          # count hardlinks only once.
          unless scanned_files.include?(file_id)
            @disk_usage += stat.size
            scanned_files.add(file_id)
          end
        end
      end
    else
      @file_count = 1
      @disk_usage = path.lstat.size
    end
  end
end
