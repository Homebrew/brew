# typed: strict
# frozen_string_literal: true

class MacOSRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :timeout, Integer
  const :cleanup, T::Boolean

  sig { returns({ name: String, runner: String, timeout: Integer, cleanup: T::Boolean }) }
  def to_h
    {
      name:    name,
      runner:  runner,
      timeout: timeout,
      cleanup: cleanup,
    }
  end
end
