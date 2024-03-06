# typed: true
# frozen_string_literal: true

require "system_command"

module Utils
  # Helper functions for interacting with tar files.
  module Tar
    class << self
      include SystemCommand::Mixin

      TAR_FILE_EXTENSIONS = %w[.tar .tb2 .tbz .tbz2 .tgz .tlz .txz .tZ].freeze

      def available?
        executable.present?
      end

      def executable
        return @executable if defined?(@executable)

        gnu_tar_gtar_path = HOMEBREW_PREFIX/"opt/gnu-tar/bin/gtar"
        gnu_tar_gtar = gnu_tar_gtar_path if gnu_tar_gtar_path.executable?
        @executable = which("gtar") || gnu_tar_gtar || which("tar")
      end

      def validate_file(path)
        return unless available?

        path = Pathname.new(path)
        return unless TAR_FILE_EXTENSIONS.include? path.extname

        stdout, _, status = system_command(executable, args: ["--list", "--file", path], print_stderr: false)
        odie "#{path} is not a valid tar file!" if !status.success? || stdout.blank?
      end

      def clear_executable_cache
        remove_instance_variable(:@executable) if defined?(@executable)
      end
    end
  end
end
