# typed: true
# frozen_string_literal: true

require_relative "directory"

module UnpackStrategy
  # Strategy for unpacking Mercurial repositories.
  class Mercurial < Directory
    def self.can_extract?(path)
      super && (path/".hg").directory?
    end

    private

    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "hg",
                      args:    ["--cwd", path, "archive", "--subrepos", "-y", "-t", "files", unpack_dir],
                      env:     { "PATH" => PATH.new(Formula["mercurial"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
