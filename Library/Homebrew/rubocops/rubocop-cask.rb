# typed: strict
# frozen_string_literal: true

require "rubocop"

require_relative "cask/constants/stanza"

require_relative "cask/ast/stanza"
require_relative "cask/ast/cask_header"
require_relative "cask/ast/cask_block"
require_relative "cask/extend/node"
require_relative "cask/mixin/cask_help"
require_relative "cask/mixin/on_homepage_stanza"
require_relative "cask/mixin/on_url_stanza"
require_relative "cask/array_alphabetization"
require_relative "cask/desc"
require_relative "cask/discontinued"
require_relative "cask/homepage_url_styling"
require_relative "cask/no_overrides"
require_relative "cask/on_system_conditionals"
require_relative "cask/shared_filelist_glob"
require_relative "cask/stanza_order"
require_relative "cask/stanza_grouping"
require_relative "cask/uninstall_methods_order"
require_relative "cask/url"
require_relative "cask/url_legacy_comma_separators"
require_relative "cask/variables"
