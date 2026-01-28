# typed: strict
# frozen_string_literal: true

class MacOSRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :timeout, Integer
  const :cleanup, T::Boolean
  prop  :testing_formulae, T::Array[String], default: []

  sig {
    returns({
      name:             String,
      runner:           String,
      timeout:          Integer,
      cleanup:          T::Boolean,
      testing_formulae: String,
    })
  }
  def to_h
    {
      name:,
      runner:,
      timeout:,
      cleanup:,
      testing_formulae: testing_formulae.join(","),
    }
  end
end
