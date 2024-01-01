# typed: true
# frozen_string_literal: true

OFFICIAL_CASK_TAPS = %w[
  cask
  cask-fonts
  cask-versions
].freeze

OFFICIAL_CMD_TAPS = {
  "homebrew/aliases"           => ["alias", "unalias"],
  "homebrew/autoupdate"        => ["autoupdate"],
  "homebrew/bundle"            => ["bundle"],
  "homebrew/command-not-found" => ["command-not-found-init", "which-formula", "which-update"],
  "homebrew/test-bot"          => ["test-bot"],
  "homebrew/services"          => ["services"],
}.freeze

DEPRECATED_OFFICIAL_TAPS = %w[
  apache
  binary
  cask-drivers
  cask-eid
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
