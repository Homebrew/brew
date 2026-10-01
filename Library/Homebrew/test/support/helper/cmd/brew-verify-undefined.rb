# typed: strict
# frozen_string_literal: true

require "cli/parser"
require "utils/output"

UNDEFINED_CONSTANTS = %w[
  AbstractDownloadStrategy
  Addressable
  Base64
  CacheStore
  Cask::Cask
  Cask::CaskLoader
  Completions
  Concurrent
  CSV
  Formula
  Formulary
  GitRepository
  Homebrew::API
  Homebrew::Manpages
  Homebrew::Settings
  JSONSchemer
  Kramdown
  MachO
  Metafiles
  MethodSource
  Minitest
  Nokogiri
  OS::Mac::Version
  PatchELF
  Plist
  Pry
  ProgressBar
  PyCall
  REXML
  Red
  Redcarpet
  RSpec
  RuboCop
  RubyProf
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
  Warnings
  YARD
].freeze

UNDEFINED_CONSTANTS_AFTER_REQUIRE = T.let({
  "api"                             => %w[Base64 Concurrent Homebrew::DownloadQueue Plist],
  "cask/artifact/pkg"               => %w[Plist],
  "dev-cmd/formula-analytics"       => %w[InfluxDBClient3 PyCall],
  "dev-cmd/generate-cask-ci-matrix" => %w[Cask::Cask Cask::CaskLoader],
  "downloadable"                    => %w[Concurrent],
  "extend/os/mac/extend/pathname"   => %w[MachO],
  "formula_cellar_checks"           => %w[Plist],
  "keg"                             => %w[MachO],
  "livecheck/livecheck"             => %w[Addressable],
  "os/mac/xcode"                    => %w[Plist],
  "service"                         => %w[Plist],
  "services/cli"                    => %w[Plist],
}.freeze, T::Hash[String, T::Array[String]])

module Homebrew
  module Cmd
    class VerifyUndefined < AbstractCommand
      sig { override.void }
      def run; end
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
  # The constant name is iterated from the list above.
  # rubocop:disable Sorbet/ConstantsFromStrings
  Object.const_get(constant_name)
  # rubocop:enable Sorbet/ConstantsFromStrings
  Utils::Output.ofail "#{constant_name} should not be defined at startup"
rescue NameError
  # We expect this to error as it should not be defined.
end

UNDEFINED_CONSTANTS_AFTER_REQUIRE.each do |require_path, constant_names|
  require require_path

  constant_names.each do |constant_name|
    # The constant name is iterated from the list above.
    # rubocop:disable Sorbet/ConstantsFromStrings
    Object.const_get(constant_name)
    # rubocop:enable Sorbet/ConstantsFromStrings
    Utils::Output.ofail "#{constant_name} should not be defined after requiring #{require_path}"
  rescue NameError
    # We expect this to error as it should not be defined.
  end
end
