# typed: strict
# frozen_string_literal: true

class MacOSRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :timeout, Integer
  const :cleanup, T::Boolean
  const :target_macos, T.nilable(String), default: nil
  prop  :testing_formulae, T::Array[String], default: []

  sig {
    returns({
      name:             String,
      runner:           String,
      timeout:          Integer,
      cleanup:          T::Boolean,
      target_macos:     T.nilable(String),
      testing_formulae: String,
    })
  }
  def to_h
    {
      name:,
      runner:,
      timeout:,
      cleanup:,
      target_macos:,
      testing_formulae: testing_formulae.join(","),
    }
  end
end
