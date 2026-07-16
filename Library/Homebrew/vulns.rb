# typed: strict
# frozen_string_literal: true

require "vulns/semver"
require "vulns/cvss"
require "vulns/vulnerability"
require "vulns/osv"
require "vulns/scanner"
require "vulns/output"

module Homebrew
  # Checks formulae for known security vulnerabilities via OSV.dev.
  # See {Homebrew::Cmd::Vulns} for the user-facing command.
  module Vulns
  end
end
