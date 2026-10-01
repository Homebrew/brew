# typed: strict
# frozen_string_literal: true

require "delegate"
require "etc"

require "system_command"

# A system user.
class User < SimpleDelegator
  include SystemCommand::Mixin

  # Return whether the user has an active GUI session.
  sig { returns(T::Boolean) }
  def gui?
    out, _, status = system_command("who").to_a
    return false unless status.success?

    out.lines
       .map(&:split)
       .any? { |user, type,| to_s == user && type == "console" }
  end

  # Return the current user.
  sig { returns(T.nilable(T.attached_class)) }
  def self.current
    return @current if defined?(@current)

    pwuid = Etc.getpwuid(Process.euid)
    return if pwuid.nil?

    @current = T.let(new(pwuid.name), T.nilable(T.attached_class))
  end

  # This explicit delegator exists to make to_s visible to sorbet.
  sig { returns(String) }
  def to_s = __getobj__.to_s
end
