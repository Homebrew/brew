# typed: strict
# frozen_string_literal: true

require "cli/parser"

UNDEFINED_CONSTANTS = %w[
  AbstractDownloadStrategy
  Addressable
  Base64
  CacheStore
  Cask::Cask
  Cask::CaskLoader
  Completions
  CSV
  Formula
  Formulary
  GitRepository
  Homebrew::API
  Homebrew::Manpages
  Homebrew::Settings
  JSONSchemer
  Kramdown
  Metafiles
  MethodSource
  Minitest
  Nokogiri
  OS::Mac::Version
  PatchELF
  Pry
  ProgressBar
  REXML
  Red
  RSpec
  RuboCop
  StackProf
  Spoom
  Tap
  Tapioca
  UnpackStrategy
  Utils::Analytics
  Utils::Backtrace
  Utils::Bottles
  Utils::Curl
  Utils::Fork
  Utils::Git
  Utils::GitHub
  Utils::Link
  Utils::Svn
  Uri
  Vernier
  YARD
].freeze

module Homebrew
  module Cmd
    class VerifyUndefined < AbstractCommand
    end
  end
end

parser = Homebrew::CLI::Parser.new(Homebrew::Cmd::VerifyUndefined) do
  usage_banner <<~EOS
    `verify-undefined`

    Verifies that the following constants have not been defined
    at startup to make sure that startup times stay consistent.

    Constants:
    #{UNDEFINED_CONSTANTS.join("\n")}
  EOS
end

parser.parse

UNDEFINED_CONSTANTS.each do |constant_name|
  Object.const_get(constant_name)
  ofail "#{constant_name} should not be defined at startup"
rescue NameError
  # We expect this to error as it should not be defined.
end
