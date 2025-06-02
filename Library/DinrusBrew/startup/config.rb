# typed: true
# frozen_string_literal: true

raise "DINRUSBREW_BREW_FILE was not exported! Please call bin/brew directly!" unless ENV["DINRUSBREW_BREW_FILE"]

# Path to `bin/brew` main executable in `DINRUSBREW_PREFIX`
# Used for e.g. permissions checks.
DINRUSBREW_ORIGINAL_BREW_FILE = Pathname(ENV.fetch("DINRUSBREW_ORIGINAL_BREW_FILE")).freeze

# Path to the executable that should be used to run `brew`.
# This may be DINRUSBREW_ORIGINAL_BREW_FILE or DINRUSBREW_BREW_WRAPPER.
DINRUSBREW_BREW_FILE = Pathname(ENV.fetch("DINRUSBREW_BREW_FILE")).freeze

# Where we link under
DINRUSBREW_PREFIX = Pathname(ENV.fetch("DINRUSBREW_PREFIX")).freeze

# Where `.git` is found
DINRUSBREW_REPOSITORY = Pathname(ENV.fetch("DINRUSBREW_REPOSITORY")).freeze

# Where we store most of DinrusBrew, taps and various metadata
DINRUSBREW_LIBRARY = Pathname(ENV.fetch("DINRUSBREW_LIBRARY")).freeze

# Where shim scripts for various build and SCM tools are stored
DINRUSBREW_SHIMS_PATH = (DINRUSBREW_LIBRARY/"DinrusBrew/shims").freeze

# Where external data that has been incorporated into DinrusBrew is stored
DINRUSBREW_DATA_PATH = (DINRUSBREW_LIBRARY/"DinrusBrew/data").freeze

# Where we store symlinks to currently linked kegs
DINRUSBREW_LINKED_KEGS = (DINRUSBREW_PREFIX/"var/homebrew/linked").freeze

# Where we store symlinks to currently version-pinned kegs
DINRUSBREW_PINNED_KEGS = (DINRUSBREW_PREFIX/"var/homebrew/pinned").freeze

# Where we store lock files
DINRUSBREW_LOCKS = (DINRUSBREW_PREFIX/"var/homebrew/locks").freeze

# Where we store built products
DINRUSBREW_CELLAR = Pathname(ENV.fetch("DINRUSBREW_CELLAR")).freeze

# Where we store Casks
DINRUSBREW_CASKROOM = Pathname(ENV.fetch("DINRUSBREW_CASKROOM")).freeze

# Where downloads (bottles, source tarballs, etc.) are cached
DINRUSBREW_CACHE = Pathname(ENV.fetch("DINRUSBREW_CACHE")).freeze

# Where formulae installed via URL are cached
DINRUSBREW_CACHE_FORMULA = (DINRUSBREW_CACHE/"Formula").freeze

# Where build, postinstall and test logs of formulae are written to
DINRUSBREW_LOGS = Pathname(ENV.fetch("DINRUSBREW_LOGS")).expand_path.freeze

# Must use `/tmp` instead of `TMPDIR` because long paths break Unix domain sockets
DINRUSBREW_TEMP = Pathname(ENV.fetch("DINRUSBREW_TEMP")).then do |tmp|
  tmp.mkpath unless tmp.exist?
  tmp.realpath
end.freeze

# Where installed taps live
DINRUSBREW_TAP_DIRECTORY = (DINRUSBREW_LIBRARY/"Taps").freeze

# The Ruby path and args to use for forked Ruby calls
DINRUSBREW_RUBY_EXEC_ARGS = [
  RUBY_PATH,
  ENV.fetch("DINRUSBREW_RUBY_WARNINGS"),
  ENV.fetch("DINRUSBREW_RUBY_DISABLE_OPTIONS"),
].freeze
