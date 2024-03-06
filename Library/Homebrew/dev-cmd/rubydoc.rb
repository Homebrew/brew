# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def rubydoc_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Generate Homebrew's RubyDoc documentation.
      EOS
      switch "--only-public",
             description: "Only generate public API documentation."
      switch "--open",
             description: "Open generated documentation in a browser."
    end
  end

  sig { void }
  def rubydoc
    args = rubydoc_args.parse

    Homebrew.install_bundler_gems!(groups: ["doc"])

    HOMEBREW_LIBRARY_PATH.cd do
      no_api_args = if args.only_public?
        ["--hide-api", "private", "--hide-api", "internal"]
      else
        []
      end

      system "bundle", "exec", "yard", "doc", "--output", "doc", *no_api_args

      exec_browser "file://#{HOMEBREW_LIBRARY_PATH}/doc/index.html" if args.open?
    end
  end
end
