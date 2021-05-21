# typed: strict
# frozen_string_literal: true

require_relative "load_path"

require "active_support/core_ext/array/conversions"

require "utils/sorbet"

require "rubocop-performance"
require "rubocop-rails"
require "rubocop-rspec"
require "rubocop-sorbet"

require "rubocops/io_read"
require "rubocops/shell_commands"

require "rubocops/formula_desc"
require "rubocops/components_order"
require "rubocops/components_redundancy"
require "rubocops/dependency_order"
require "rubocops/homepage"
require "rubocops/text"
require "rubocops/caveats"
require "rubocops/checksum"
require "rubocops/patches"
require "rubocops/conflicts"
require "rubocops/options"
require "rubocops/urls"
require "rubocops/lines"
require "rubocops/livecheck"
require "rubocops/class"
require "rubocops/uses_from_macos"
require "rubocops/files"
require "rubocops/keg_only"
require "rubocops/version"
require "rubocops/deprecate_disable"
require "rubocops/bottle"
require "rubocops/go"

require "rubocops/rubocop-cask"
