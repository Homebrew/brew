# typed: strict
# frozen_string_literal: true

require "help"

module Homebrew
  sig { returns(T.noreturn) }
  def help
    Help.help
  end
end
