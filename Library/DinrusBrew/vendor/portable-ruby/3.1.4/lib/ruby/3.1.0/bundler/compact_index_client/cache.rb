# frozen_string_literal: true

require_relative "gem_parser"

module Bundler
  class CompactIndexClient
    class Cache
      attr_reader :directory

      def initialize(directory)
        @directory = Pathname.new(directory).expand_path
        info_roots.each do |dir|
          SharedHelpers.filesystem_access(dir) do
            FileUtils.mkdir_p(dir)
          end
        end
      end

      def names
        lines(names_path)
      end

      def names_path
        directory.join("names")
      end

      def versions
        versions_by_name = Hash.new {|hash, key| hash[key] = [] }
        info_checksums_by_name = {}

        lines(versions_path).each do |line|
          name, versions_string, info_checksum = line.split(" ", 3)
          info_checksums_by_name[name] = info_checksum || ""
          versions_string.split(",").each do |version|
            if version.start_with?("-")
              version = version[1..-1].split("-", 2).unshift(name)
              versions_by_name[name].delete(version)
            else
              version = version.split("-", 2).unshift(name)
              versions_by_name[name] << version
            end
          end
        end

        [versions_by_name, info_checksums_by_name]
      end

      def versions_path
        directory.join("versions")
      end

      def checksums
        checksums = {}

        lines(versions_path).each do |line|
          name, _, checksum = line.split(" ", 3)
          checksums[name] = checksum
        end

        checksums
      end

      def dependencies(name)
        lines(info_path(name)).map do |line|
          parse_gem(line)
        end
      end

      def info_path(name)
        name = name.to_s
        if name =~ /[^a-z0-9_-]/
          name += "-#{SharedHelpers.digest(:MD5).hexdigest(name).downcase}"
          info_roots.last.join(name)
        else
          info_roots.first.join(name)
        end
      end

      private

      def lines(path)
        return [] unless path.file?
        lines = SharedHelpers.filesystem_access(path, :read, &:read).split("\n")
        header = lines.index("---")
        header ? lines[header + 1..-1] : lines
      end

      def parse_gem(line)
        @dependency_parser ||= GemParser.new
        @dependency_parser.parse(line)
      end

      def info_roots
        [
          directory.join("info"),
          directory.join("info-special-characters"),
        ]
      end
    end
  end
end
