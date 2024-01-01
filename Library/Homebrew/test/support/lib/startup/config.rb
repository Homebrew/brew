# typed: true
# frozen_string_literal: true

raise "HOMEBREW_BREW_FILE was not exported! Please call bin/brew directly!" unless ENV["HOMEBREW_BREW_FILE"]

HOMEBREW_BREW_FILE = Pathname.new(ENV.fetch("HOMEBREW_BREW_FILE")).freeze

TEST_TMPDIR = ENV.fetch("HOMEBREW_TEST_TMPDIR") do |k|
  dir = Dir.mktmpdir("homebrew-tests-", ENV.fetch("HOMEBREW_TEMP"))
  at_exit do
    # Child processes inherit this at_exit handler, but we don't want them
    # to clean TEST_TMPDIR up prematurely (i.e. when they exit early for a test).
    FileUtils.remove_entry(dir) unless ENV["HOMEBREW_TEST_NO_EXIT_CLEANUP"]
  end
  ENV[k] = dir
end.freeze

# Paths pointing into the Homebrew code base that persist across test runs
HOMEBREW_SHIMS_PATH = (HOMEBREW_LIBRARY_PATH/"shims").freeze

# Where external data that has been incorporated into Homebrew is stored
HOMEBREW_DATA_PATH = (HOMEBREW_LIBRARY_PATH/"data").freeze

# Paths redirected to a temporary directory and wiped at the end of the test run
HOMEBREW_PREFIX        = (Pathname(TEST_TMPDIR)/"prefix").freeze
HOMEBREW_REPOSITORY    = HOMEBREW_PREFIX.dup.freeze
HOMEBREW_LIBRARY       = (HOMEBREW_REPOSITORY/"Library").freeze
HOMEBREW_CACHE         = (HOMEBREW_PREFIX.parent/"cache").freeze
HOMEBREW_CACHE_FORMULA = (HOMEBREW_PREFIX.parent/"formula_cache").freeze
HOMEBREW_LINKED_KEGS   = (HOMEBREW_PREFIX.parent/"linked").freeze
HOMEBREW_PINNED_KEGS   = (HOMEBREW_PREFIX.parent/"pinned").freeze
HOMEBREW_LOCKS         = (HOMEBREW_PREFIX.parent/"locks").freeze
HOMEBREW_CELLAR        = (HOMEBREW_PREFIX.parent/"cellar").freeze
HOMEBREW_LOGS          = (HOMEBREW_PREFIX.parent/"logs").freeze
HOMEBREW_TEMP          = (HOMEBREW_PREFIX.parent/"temp").freeze
HOMEBREW_RUBY_EXEC_ARGS = [
  RUBY_PATH,
  ENV.fetch("HOMEBREW_RUBY_WARNINGS"),
  ENV.fetch("HOMEBREW_RUBY_DISABLE_OPTIONS"),
  "-I", HOMEBREW_LIBRARY_PATH/"test/support/lib"
].freeze

TEST_FIXTURE_DIR = (HOMEBREW_LIBRARY_PATH/"test/support/fixtures").freeze

TESTBALL_SHA256 = "91e3f7930c98d7ccfb288e115ed52d06b0e5bc16fec7dce8bdda86530027067b"
TESTBALL_PATCHES_SHA256 = "799c2d551ac5c3a5759bea7796631a7906a6a24435b52261a317133a0bfb34d9"
PATCH_A_SHA256 = "83404f4936d3257e65f176c4ffb5a5b8d6edd644a21c8d8dcc73e22a6d28fcfa"
PATCH_B_SHA256 = "57958271bb802a59452d0816e0670d16c8b70bdf6530bcf6f78726489ad89b90"

TEST_SHA256 = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
