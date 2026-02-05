# typed: strict
# frozen_string_literal: true

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
    ofail <<~EOS
      Refusing to uninstall #{reqs.to_sentence}
      because #{reqs.one? ? "it" : "they"} #{are_required_by_deps}.
      You can override this and force removal with:
        #{sample_command}
    EOS
  end

  protected

  sig { returns(String) }
  def sample_command
    "brew uninstall --ignore-dependencies #{named_args.join(" ")}"
  end

  sig { returns(String) }
  def are_required_by_deps
    "#{reqs.one? ? "is" : "are"} required by #{deps.to_sentence}, " \
      "which #{deps.one? ? "is" : "are"} currently installed"
  end
end
