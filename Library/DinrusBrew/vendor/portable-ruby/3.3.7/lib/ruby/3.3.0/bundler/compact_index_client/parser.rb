# frozen_string_literal: true

module Bundler
  class CompactIndexClient
    class Parser
      # `compact_index` - an object responding to #names, #versions, #info(name, checksum),
      #                   returning the file contents as a string
      def initialize(compact_index)
        @compact_index = compact_index
        @info_checksums = nil
        @versions_by_name = nil
        @available = nil
        @gem_parser = nil
      end

      def names
        lines(@compact_index.names)
      end

      def versions
        @versions_by_name ||= Hash.new {|hash, key| hash[key] = [] }
        @info_checksums = {}

        lines(@compact_index.versions).each do |line|
          name, versions_string, checksum = line.split(" ", 3)
          @info_checksums[name] = checksum || ""
          versions_string.split(",") do |version|
            delete = version.delete_prefix!("-")
            version = version.split("-", 2).unshift(name)
            if delete
              @versions_by_name[name].delete(version)
            else
              @versions_by_name[name] << version
            end
          end
        end

        @versions_by_name
      end

      def info(name)
        data = @compact_index.info(name, info_checksums[name])
        lines(data).map {|line| gem_parser.parse(line).unshift(name) }
      end

      def available?
        return @available unless @available.nil?
        @available = !info_checksums.empty?
      end

      private

      def info_checksums
        @info_checksums ||= lines(@compact_index.versions).each_with_object({}) do |line, checksums|
          parse_version_checksum(line, checksums)
        end
      end

      def lines(data)
        return [] if data.nil? || data.empty?
        lines = data.split("\n")
        header = lines.index("---")
        header ? lines[header + 1..-1] : lines
      end

      def gem_parser
        @gem_parser ||= GemParser.new
      end

      # This is mostly the same as `split(" ", 3)` but it avoids allocating extra objects.
      # This method gets called at least once for every gem when parsing versions.
      def parse_version_checksum(line, checksums)
        return unless (name_end = line.index(" ")) # Artifactory bug causes blank lines in artifactor index files
        return unless (checksum_start = line.index(" ", name_end + 1) + 1)
        checksum_end = line.size - checksum_start

        line.freeze # allows slicing into the string to not allocate a copy of the line
        name = line[0, name_end]
        checksum = line[checksum_start, checksum_end]
        checksums[name.freeze] = checksum # freeze name since it is used as a hash key
      end
    end
  end
end
