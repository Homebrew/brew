# typed: strict
# frozen_string_literal: true

OFFICIAL_CASK_TAPS = %w[
  cask
].freeze

OFFICIAL_CMD_TAPS = T.let({
  "homebrew/aliases"           => ["alias", "unalias"],
  "homebrew/bundle"            => ["bundle"],
  "homebrew/command-not-found" => ["command-not-found-init", "which-formula", "which-update"],
  "homebrew/test-bot"          => ["test-bot"],
  "homebrew/services"          => ["services"],
}.freeze, T::Hash[String, T::Array[String]])

DEPRECATED_OFFICIAL_TAPS = %w[
  apache
  binary
  cask-drivers
  cask-eid
  cask-fonts
  cask-versions
  completions
  devel-only
  dupes
  emacs
  fuse
  games
  gui
  head-only
  livecheck
  nginx
  php
  python
  science
  tex
  versions
  x11
].freeze
