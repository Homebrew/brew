# typed: strict
# frozen_string_literal: true

require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def docs_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Open Homebrew's online documentation at <#{HOMEBREW_DOCS_WWW}> in a browser.
      EOS
    end
  end

  sig { void }
  def docs
    exec_browser HOMEBREW_DOCS_WWW
  end
end
