# frozen_string_literal: true

require_relative "../vendored_fileutils"
require "rubygems/package"

module Bundler
  class CompactIndexClient
    # write cache files in a way that is robust to concurrent modifications
    # if digests are given, the checksums will be verified
    class CacheFile
      DEFAULT_FILE_MODE = 0o644
      private_constant :DEFAULT_FILE_MODE

      class Error < RuntimeError; end
      class ClosedError < Error; end

      class DigestMismatchError < Error
        def initialize(digests, expected_digests)
          super "Calculated checksums #{digests.inspect} did not match expected #{expected_digests.inspect}."
        end
      end

      # Initialize with a copy of the original file, then yield the instance.
      def self.copy(path, &block)
        new(path) do |file|
          file.initialize_digests

          SharedHelpers.filesystem_access(path, :read) do
            path.open("rb") do |s|
              file.open {|f| IO.copy_stream(s, f) }
            end
          end

          yield file
        end
      end

      # Write data to a temp file, then replace the original file with it verifying the digests if given.
      def self.write(path, data, digests = nil)
        return unless data
        new(path) do |file|
          file.digests = digests
          file.write(data)
        end
      end

      attr_reader :original_path, :path

      def initialize(original_path, &block)
        @original_path = original_path
        @perm = original_path.file? ? original_path.stat.mode : DEFAULT_FILE_MODE
        @path = original_path.sub(/$/, ".#{$$}.tmp")
        return unless block_given?
        begin
          yield self
        ensure
          close
        end
      end

      def size
        path.size
      end

      # initialize the digests using CompactIndexClient::SUPPORTED_DIGESTS, or a subset based on keys.
      def initialize_digests(keys = nil)
        @digests = keys ? SUPPORTED_DIGESTS.slice(*keys) : SUPPORTED_DIGESTS.dup
        @digests.transform_values! {|algo_class| SharedHelpers.digest(algo_class).new }
      end

      # reset the digests so they don't contain any previously read data
      def reset_digests
        @digests&.each_value(&:reset)
      end

      # set the digests that will be verified at the end
      def digests=(expected_digests)
        @expected_digests = expected_digests

        if @expected_digests.nil?
          @digests = nil
        elsif @digests
          @digests = @digests.slice(*@expected_digests.keys)
        else
          initialize_digests(@expected_digests.keys)
        end
      end

      # remove this method when we stop generating md5 digests for legacy etags
      def md5
        @digests && @digests["md5"]
      end

      def digests?
        @digests&.any?
      end

      # Open the temp file for writing, reusing original permissions, yielding the IO object.
      def open(write_mode = "wb", perm = @perm, &block)
        raise ClosedError, "Cannot reopen closed file" if @closed
        SharedHelpers.filesystem_access(path, :write) do
          path.open(write_mode, perm) do |f|
            yield digests? ? Gem::Package::DigestIO.new(f, @digests) : f
          end
        end
      end

      # Returns false without appending when no digests since appending is too error prone to do without digests.
      def append(data)
        return false unless digests?
        open("a") {|f| f.write data }
        verify && commit
      end

      def write(data)
        reset_digests
        open {|f| f.write data }
        commit!
      end

      def commit!
        verify || raise(DigestMismatchError.new(@base64digests, @expected_digests))
        commit
      end

      # Verify the digests, returning true on match, false on mismatch.
      def verify
        return true unless @expected_digests && digests?
        @base64digests = @digests.transform_values!(&:base64digest)
        @digests = nil
        @base64digests.all? {|algo, digest| @expected_digests[algo] == digest }
      end

      # Replace the original file with the temp file without verifying digests.
      # The file is permanently closed.
      def commit
        raise ClosedError, "Cannot commit closed file" if @closed
        SharedHelpers.filesystem_access(original_path, :write) do
          FileUtils.mv(path, original_path)
        end
        @closed = true
      end

      # Remove the temp file without replacing the original file.
      # The file is permanently closed.
      def close
        return if @closed
        FileUtils.remove_file(path) if @path&.file?
        @closed = true
      end
    end
  end
end
