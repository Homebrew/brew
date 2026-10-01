# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "utils/output"

module Homebrew
  # ExecutablesDB represents a DB associating formulae to the binaries they
  # provide.
  class ExecutablesDB
    include Utils::Output::Mixin

    DB_LINE_REGEX = /^(?<name>.*?)(?:\([^)]*\))?:(?<exes_line>.*)?$/

    # initialize a new DB with the given filename. The file will be used to
    # populate the DB if it exists. It'll be created or overridden when saving the
    # DB.
    # @see #save!
    sig { params(filename: String).void }
    def initialize(filename)
      @filename = filename
      @exes = T.let({}, T::Hash[String, T::Array[String]])

      return unless File.file? @filename

      File.new(@filename).each do |line|
        matches = line.match DB_LINE_REGEX
        next unless matches

        @exes[matches[:name].to_s] ||= matches[:exes_line]&.split || []
      end
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def to_hash
      @exes.transform_values(&:dup)
    end

    sig { params(bottle_json_dir: T.nilable(String), removed_formulae: T::Array[String]).void }
    def update!(bottle_json_dir: nil, removed_formulae: [])
      if (json_dir = bottle_json_dir.presence) && Pathname(json_dir).directory?
        Dir[File.join(json_dir, "**", "*.bottle.json")].each do |path|
          bottle_json = begin
            T.cast(JSON.parse(File.read(path)), T::Hash[String, T::Hash[String, T.untyped]])
          rescue JSON::ParserError => e
            opoo "Skipping #{path}: #{e.message}"
            next
          end

          bottle_json.each do |full_name, hash|
            path_exec_file_tags = T.cast(
              hash.dig("bottle", "tags") || {},
              T::Hash[String, T::Hash[String, T.untyped]],
            ).values.select { |tag_hash| tag_hash.key?("path_exec_files") }

            if path_exec_file_tags.empty?
              opoo "Skipping #{full_name}: no `path_exec_files` in #{path}"
              next
            end

            @exes[hash.dig("formula", "name").to_s.presence || File.basename(full_name, ".rb")] =
              path_exec_file_tags.flat_map { |tag_hash| Array(tag_hash["path_exec_files"]) }
                                 .map { |file| File.basename(file.to_s) }
                                 .uniq
                                 .sort
          end
        end
      end

      removed_formulae.uniq.sort.each do |name|
        next unless @exes.delete(name)

        puts "Removed #{name}"
      end
    end

    # save the DB in the underlying file
    sig { void }
    def save!
      File.open(@filename, "w") do |f|
        @exes.sort.each do |formula, binaries|
          f.write "#{formula}:#{binaries.join(" ")}\n"
        end
      end
    end
  end
end
