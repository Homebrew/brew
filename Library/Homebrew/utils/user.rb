# typed: true
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
    out, _, status = system_command "who"
    return false unless status.success?

    out.lines
       .map(&:split)
       .any? { |user, type,| user == self && type == "console" }
  end

  # Return the current user.
  sig { returns(T.nilable(T.attached_class)) }
  def self.current
    return @current if defined?(@current)

    pwuid = Etc.getpwuid(Process.euid)
    return if pwuid.nil?

    @current = new(pwuid.name)
  end
end
