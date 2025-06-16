# typed: strict
# frozen_string_literal: true

OFFICIAL_CASK_TAPS = %w[
  cask
].freeze

OFFICIAL_CMD_TAPS = T.let({
  "homebrew/command-not-found" => ["command-not-found-init", "which-formula", "which-update"],
  "homebrew/test-bot"          => ["test-bot"],
}.freeze, T::Hash[String, T::Array[String]])

DEPRECATED_OFFICIAL_TAPS = %w[
  aliases
  apache
  binary
  bundle
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
  linux-fonts
  livecheck
  nginx
  php
  python
  science
  services
  tex
  versions
  x11
].freeze
