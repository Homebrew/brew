# typed: strict
# frozen_string_literal: true

class LinuxRunnerSpec < T::Struct
  const :name, String
  const :runner, String
  const :container, T.nilable({ image: String, options: String })
  const :workdir, T.nilable(String)
  const :timeout, Integer
  const :cleanup, T::Boolean
  prop  :testing_formulae, T::Array[String], default: []

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_h
    {
      name:,
      runner:,
      container:,
      workdir:,
      timeout:,
      cleanup:,
      testing_formulae: testing_formulae.join(","),
    }.compact
  end
end
