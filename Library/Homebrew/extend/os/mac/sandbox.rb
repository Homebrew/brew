# typed: strict
# frozen_string_literal: true

class Sandbox
  sig { returns(T::Boolean) }
  def self.available?
    File.executable?(SANDBOX_EXEC)
  end
end
