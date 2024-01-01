# typed: true
# frozen_string_literal: true

# Apple's gzip also uses zlib so use the same buffer size here.
# https://github.com/apple-oss-distributions/file_cmds/blob/file_cmds-400/gzip/gzip.c#L147
GZIP_BUFFER_SIZE = 64 * 1024

module Utils
  # Helper functions for creating gzip files.
  module Gzip
    sig {
      params(
        path:      T.any(String, Pathname),
        mtime:     T.any(Integer, Time),
        orig_name: String,
        output:    T.any(String, Pathname),
      ).returns(Pathname)
    }
    def self.compress_with_options(path, mtime: ENV["SOURCE_DATE_EPOCH"].to_i, orig_name: File.basename(path),
                                   output: "#{path}.gz")
      # Ideally, we would just set mtime = 0 if SOURCE_DATE_EPOCH is absent, but Ruby's
      # Zlib::GzipWriter does not properly handle the case of setting mtime = 0:
      # https://bugs.ruby-lang.org/issues/16285
      #
      # This was fixed in https://github.com/ruby/zlib/pull/10. Remove workaround
      # once we are using zlib gem version 1.1.0 or newer.
      if mtime.to_i.zero?
        odebug "Setting `mtime = 1` to avoid zlib gem bug when `mtime == 0`."
        mtime = 1
      end

      File.open(path, "rb") do |fp|
        odebug "Creating gzip file at #{output}"
        gz = Zlib::GzipWriter.open(output)
        gz.mtime = mtime
        gz.orig_name = orig_name
        gz.write(fp.read(GZIP_BUFFER_SIZE)) until fp.eof?
      ensure
        # GzipWriter should be closed in case of error as well
        gz.close
      end

      FileUtils.rm_f path
      Pathname.new(output)
    end

    sig {
      params(
        paths:        T.any(String, Pathname),
        reproducible: T::Boolean,
        mtime:        T.any(Integer, Time),
      ).returns(T::Array[Pathname])
    }
    def self.compress(*paths, reproducible: true, mtime: ENV["SOURCE_DATE_EPOCH"].to_i)
      if reproducible
        paths.map do |path|
          compress_with_options(path, mtime: mtime)
        end
      else
        paths.map do |path|
          safe_system "gzip", path
          Pathname.new("#{path}.gz")
        end
      end
    end
  end
end
