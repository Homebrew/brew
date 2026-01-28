# typed: true
# frozen_string_literal: true

module Test
  module Helper
    module Files
      def self.find_files
        return [] unless File.exist?(TEST_TMPDIR)

        Find.find(TEST_TMPDIR)
            .reject { |f| File.basename(f) == ".DS_Store" }
            .reject { |f| TEST_DIRECTORIES.include?(Pathname(f)) }
            .map { |f| f.sub(TEST_TMPDIR, "") }
      end
    end
  end
end
