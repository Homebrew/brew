# typed: strict
# frozen_string_literal: true

require "development_tools"
require "messages"
require "utils/output"

# Needed to handle circular require dependency.
# rubocop:disable Lint/EmptyClass
class FormulaInstaller; end
# rubocop:enable Lint/EmptyClass
require "reinstall/reinstall"

require "extend/os/reinstall"
