# typed: true
# frozen_string_literal: true

require "system_command"

module UnpackStrategy
  # Strategy for unpacking Fossil repositories.
  class Fossil
    include UnpackStrategy
    extend SystemCommand::Mixin

    sig { returns(T::Array[String]) }
    def self.extensions
      []
    end

    def self.can_extract?(path)
      return false unless path.magic_number.match?(/\ASQLite format 3\000/n)

      # Fossil database is made up of artifacts, so the `artifact` table must exist.
      query = "select count(*) from sqlite_master where type = 'view' and name = 'artifact'"
      system_command("sqlite3", args: [path, query]).stdout.to_i == 1
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      args = if @ref_type && @ref
        [@ref]
      else
        []
      end

      system_command! "fossil",
                      args:    ["open", path, *args],
                      chdir:   unpack_dir,
                      env:     { "PATH" => PATH.new(Formula["fossil"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
