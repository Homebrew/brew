# typed: true
# frozen_string_literal: true

raise "DINRUSBREW_BREW_FILE was not exported! Please call bin/brew directly!" unless ENV["DINRUSBREW_BREW_FILE"]

DINRUSBREW_ORIGINAL_BREW_FILE = Pathname.new(ENV.fetch("DINRUSBREW_ORIGINAL_BREW_FILE")).freeze
DINRUSBREW_BREW_FILE = Pathname.new(ENV.fetch("DINRUSBREW_BREW_FILE")).freeze

TEST_TMPDIR = ENV.fetch("DINRUSBREW_TEST_TMPDIR") do |k|
  dir = Dir.mktmpdir("homebrew-tests-", ENV.fetch("DINRUSBREW_TEMP"))
  at_exit do
    # Child processes inherit this at_exit handler, but we don't want them
    # to clean TEST_TMPDIR up prematurely (i.e. when they exit early for a test).
    FileUtils.remove_entry(dir) unless ENV["DINRUSBREW_TEST_NO_EXIT_CLEANUP"]
  end
  ENV[k] = dir
end.freeze

# Paths pointing into the DinrusBrew code base that persist across test runs
DINRUSBREW_SHIMS_PATH = (DINRUSBREW_LIBRARY_PATH/"shims").freeze

# Where external data that has been incorporated into DinrusBrew is stored
DINRUSBREW_DATA_PATH = (DINRUSBREW_LIBRARY_PATH/"data").freeze

# Paths redirected to a temporary directory and wiped at the end of the test run
DINRUSBREW_PREFIX        = (Pathname(TEST_TMPDIR)/"prefix").freeze
DINRUSBREW_REPOSITORY    = DINRUSBREW_PREFIX.dup.freeze
DINRUSBREW_LIBRARY       = (DINRUSBREW_REPOSITORY/"Library").freeze
DINRUSBREW_CACHE         = (DINRUSBREW_PREFIX.parent/"cache").freeze
DINRUSBREW_CACHE_FORMULA = (DINRUSBREW_PREFIX.parent/"formula_cache").freeze
DINRUSBREW_LINKED_KEGS   = (DINRUSBREW_PREFIX/"var/homebrew/linked").freeze
DINRUSBREW_PINNED_KEGS   = (DINRUSBREW_PREFIX/"var/homebrew/pinned").freeze
DINRUSBREW_LOCKS         = (DINRUSBREW_PREFIX/"var/homebrew/locks").freeze
DINRUSBREW_CELLAR        = (DINRUSBREW_PREFIX/"Cellar").freeze
DINRUSBREW_LOGS          = (DINRUSBREW_PREFIX.parent/"logs").freeze
DINRUSBREW_TEMP          = (DINRUSBREW_PREFIX.parent/"temp").freeze
DINRUSBREW_TAP_DIRECTORY = (DINRUSBREW_LIBRARY/"Taps").freeze
DINRUSBREW_RUBY_EXEC_ARGS = [
  RUBY_PATH,
  ENV.fetch("DINRUSBREW_RUBY_WARNINGS"),
  ENV.fetch("DINRUSBREW_RUBY_DISABLE_OPTIONS"),
  "-I", DINRUSBREW_LIBRARY_PATH/"test/support/lib"
].freeze

TEST_FIXTURE_DIR = (DINRUSBREW_LIBRARY_PATH/"test/support/fixtures").freeze

TESTBALL_SHA256 = "91e3f7930c98d7ccfb288e115ed52d06b0e5bc16fec7dce8bdda86530027067b"
TESTBALL_PATCHES_SHA256 = "799c2d551ac5c3a5759bea7796631a7906a6a24435b52261a317133a0bfb34d9"
PATCH_A_SHA256 = "83404f4936d3257e65f176c4ffb5a5b8d6edd644a21c8d8dcc73e22a6d28fcfa"
PATCH_B_SHA256 = "57958271bb802a59452d0816e0670d16c8b70bdf6530bcf6f78726489ad89b90"
PATCH_D_SHA256 = "07c72c4463339e6e2ce235f3b26e316d4940017bf4b5236e27e757a44d67636c"

TEST_SHA256 = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
