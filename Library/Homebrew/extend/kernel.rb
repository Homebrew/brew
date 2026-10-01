# typed: strict
# frozen_string_literal: true

require "utils/shell"

# Homebrew extends Ruby's `Kernel` with its public convenience methods.
module Kernel
  # Find a command.
  #
  # @api public
  # Keep in sync with `which` in Library/Homebrew/utils.sh.
  sig { params(cmd: String, path: PATH::Elements).returns(T.nilable(Pathname)) }
  def which(cmd, path = ENV.fetch("PATH"))
    Utils::Shell.which(cmd, path)
  end

  # Calls the given block with the passed environment variables
  # added to `ENV`, then restores `ENV` afterwards.
  #
  # NOTE: This method is **not** thread-safe – other threads
  #       which happen to be scheduled during the block will also
  #       see these environment variables.
  #
  # @api public
  sig {
    type_parameters(:U)
      .params(
        hash:  T::Hash[Object, T.nilable(T.any(PATH, Pathname, String))],
        block: T.proc.returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  def with_env(hash, &block)
    Utils::Shell.with_env(hash, &block)
  end
end
