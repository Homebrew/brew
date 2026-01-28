# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/output"

module Utils
  # Helper functions for interacting with tar files.
  module Tar
    class << self
      include SystemCommand::Mixin
      include Utils::Output::Mixin

      TAR_FILE_EXTENSIONS = %w[.tar .tb2 .tbz .tbz2 .tgz .tlz .txz .tZ].freeze

      sig { returns(T::Boolean) }
      def available?
        executable.present?
      end

      sig { returns(T.nilable(Pathname)) }
      def executable
        return @executable if defined?(@executable)

        gnu_tar_gtar_path = HOMEBREW_PREFIX/"opt/gnu-tar/bin/gtar"
        gnu_tar_gtar = gnu_tar_gtar_path if gnu_tar_gtar_path.executable?
        @executable = T.let(which("gtar") || gnu_tar_gtar || which("tar"), T.nilable(Pathname))
      end

      sig { params(path: T.any(Pathname, String)).void }
      def validate_file(path)
        return unless available?

        path = Pathname.new(path)
        return unless TAR_FILE_EXTENSIONS.include? path.extname

        stdout, _, status = system_command(T.must(executable), args:         ["--list", "--file", path],
                                                               print_stderr: false).to_a
        odie "#{path} is not a valid tar file!" if !status.success? || stdout.blank?
      end

      sig { void }
      def clear_executable_cache
        remove_instance_variable(:@executable) if defined?(@executable)
      end
    end
  end
end
