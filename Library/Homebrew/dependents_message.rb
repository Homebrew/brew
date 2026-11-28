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

  sig {
    params(requireds: T::Array[T.any(String, Keg)], dependents: T::Array[String], named_args: T::Array[String],
           build: T::Boolean, commands: T::Array[String]).void
  }
  def initialize(requireds, dependents, named_args: [], build: false, commands: [])
    @reqs = requireds
    @deps = dependents
    @named_args = named_args
    @build = build
    @commands = commands
  end

  sig { void }
  def output
    verb = deps.one? ? "is" : "are"
    installed_deps = "#{Utils::Text.to_sentence(deps)}, which #{verb} currently installed"
    it_is_or_they_are = reqs.one? ? "it is" : "they are"
    to_build_or_by = @build ? "to build" : "by"
    it_or_them = reqs.one? ? "it" : "them"
    commands = @commands.map { |command| "  #{command}\n" }.join
    hint = "To stop the dependents below from requiring #{it_or_them}, run:\n#{commands}" if commands.present?
    ofail <<~EOS
      Refusing to uninstall #{Utils::Text.to_sentence(reqs)}
      because #{it_is_or_they_are} required #{to_build_or_by} #{installed_deps}.
      #{hint}You can override this and force removal with:
        brew uninstall --ignore-dependencies #{named_args.join(" ")}
    EOS
  end
end
