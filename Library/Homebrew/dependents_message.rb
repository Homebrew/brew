# typed: strict
# frozen_string_literal: true

require "utils/text"

require "utils/output"

class DependentsMessage
  include ::Utils::Output::Mixin

  sig { returns(T::Array[T.any(String, Keg)]) }
  attr_reader :reqs

  sig { returns(T::Array[String]) }
  attr_reader :deps, :named_args

  sig { params(requireds: T::Array[T.any(String, Keg)], dependents: T::Array[String], named_args: T::Array[String]).void }
  def initialize(requireds, dependents, named_args: [])
    @reqs = requireds
    @deps = dependents
    @named_args = named_args
  end

  sig { void }
  def output
    installed_deps = "#{Utils::Text.to_sentence(deps)}, which #{deps.one? ? "is" : "are"} currently installed"
    ofail <<~EOS
      Refusing to uninstall #{Utils::Text.to_sentence(reqs)}
      because #{reqs.one? ? "it is" : "they are"} required by #{installed_deps}.
      You can override this and force removal with:
        brew uninstall --ignore-dependencies #{named_args.join(" ")}
    EOS
  end
end
