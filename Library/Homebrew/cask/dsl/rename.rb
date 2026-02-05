# typed: strict
# frozen_string_literal: true

module Cask
  class DSL
    # Class corresponding to the `rename` stanza.
    class Rename
      sig { returns(String) }
      attr_reader :from, :to

      sig { params(from: String, to: String).void }
      def initialize(from, to)
        @from = from
        @to = to
      end

      sig { params(staged_path: Pathname).void }
      def perform_rename(staged_path)
        return unless staged_path.exist?

        # Find files matching the glob pattern
        matching_files = if @from.include?("*")
          staged_path.glob(@from)
        else
          [staged_path.join(@from)].select(&:exist?)
        end

        return if matching_files.empty?

        # Rename the first matching file to the target path
        source_file = matching_files.first
        return if source_file.nil?

        target_file = staged_path.join(@to)

        # Ensure target directory exists
        target_file.dirname.mkpath

        # Perform the rename
        source_file.rename(target_file.to_s) if source_file.exist?
      end

      sig { returns(T::Hash[Symbol, String]) }
      def pairs
        { from:, to: }
      end

      sig { returns(String) }
      def to_s = pairs.inspect
    end
  end
end
