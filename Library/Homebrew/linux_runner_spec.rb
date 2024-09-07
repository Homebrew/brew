# typed: strict
# frozen_string_literal: true

class LinuxRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :container, T::Hash[Symbol, String]
  const :workdir, String
  const :timeout, Integer
  const :cleanup, T::Boolean
  prop  :testing_formulae, T::Array[String], default: []

  sig {
    returns({
      name:             String,
      runner:           String,
      container:        T::Hash[Symbol, String],
      workdir:          String,
      timeout:          Integer,
      cleanup:          T::Boolean,
      testing_formulae: String,
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
      testing_formulae: testing_formulae.join(","),
    }
  end
end
