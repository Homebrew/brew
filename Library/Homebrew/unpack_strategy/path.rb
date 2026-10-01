# typed: strict
# frozen_string_literal: true

require "system_command"

module UnpackStrategy
  # A source path with cached metadata shared by archive detection strategies.
  # @api private
  class Path < Pathname
    include SystemCommand::Mixin

    sig { params(path: T.any(String, Pathname)).void }
    def initialize(path)
      super
      @magic_number = T.let(nil, T.nilable(String))
      @file_type = T.let(nil, T.nilable(String))
      @zipinfo = T.let(nil, T.nilable(T::Array[String]))
    end

    sig { returns(String) }
    def magic_number
      @magic_number ||= if directory?
        ""
      else
        # Length of the longest regex (currently Tar).
        binread(262) || ""
      end
    end

    sig { returns(String) }
    def file_type
      @file_type ||= system_command("file", args: ["-b", self], print_stderr: false).stdout.chomp
    end

    sig { returns(T::Array[String]) }
    def zipinfo
      @zipinfo ||= system_command("zipinfo", args: ["-1", self], print_stderr: false)
                   .stdout
                   .encode(Encoding::UTF_8, invalid: :replace)
                   .split("\n")
    end
  end
end
