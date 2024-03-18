# typed: strict
# frozen_string_literal: true

class LinuxRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :container, T::Hash[Symbol, String]
  const :workdir, String
  const :timeout, Integer
  const :cleanup, T::Boolean

  sig {
    returns({
      name:      String,
      runner:    String,
      container: T::Hash[Symbol, String],
      workdir:   String,
      timeout:   Integer,
      cleanup:   T::Boolean,
    })
  }
  def to_h
    {
      name:,
      runner:,
      container:,
      workdir:,
      timeout:,
      cleanup:,
    }
  end
end
