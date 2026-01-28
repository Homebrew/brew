# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "test_bot"

module Homebrew
  module Cmd
    class TestBotCmd < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `test-bot` [<options>] [<formula>]

          Tests the full lifecycle of a Homebrew change to a tap (Git repository). For example, for a GitHub Actions pull request that changes a formula `brew test-bot` will ensure the system is cleaned and set up to test the formula, install the formula, run various tests and checks on it, bottle (package) the binaries and test formulae that depend on it to ensure they aren't broken by these changes.

          Only supports GitHub Actions as a CI provider. This is because Homebrew uses GitHub Actions and it's freely available for public and private use with macOS and Linux workers.
        EOS

        switch "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--cleanup",
               description: "Clean all state from the Homebrew directory. Use with care!"
        switch "--skip-setup",
               description: "Don't check if the local system is set up correctly."
        switch "--build-from-source",
               description: "Build from source rather than building bottles."
        switch "--build-dependents-from-source",
               description: "Build dependents from source rather than testing bottles."
        switch "--junit",
               description: "generate a JUnit XML test results file."
        switch "--keep-old",
               description: "Run `brew bottle --keep-old` to build new bottles for a single platform."
        switch "--skip-relocation",
               description: "Run `brew bottle --skip-relocation` to build new bottles that don't require relocation."
        switch "--only-json-tab",
               description: "Run `brew bottle --only-json-tab` to build new bottles that do not contain a tab."
        switch "--local",
               description: "Ask Homebrew to write verbose logs under `./logs/` and set `$HOME` to `./home/`"
        flag   "--tap=",
               description: "Use the Git repository of the given tap. Defaults to the core tap for syntax checking."
        switch "--fail-fast",
               description: "Immediately exit on a failing step."
        switch "-v", "--verbose",
               description: "Print test step output in real time. Has the side effect of " \
                            "passing output as raw bytes instead of re-encoding in UTF-8."
        switch "--test-default-formula",
               description: "Use a default testing formula when not building " \
                            "a tap and no other formulae are specified."
        flag   "--root-url=",
               description: "Use the specified <URL> as the root of the bottle's URL instead of Homebrew's default."
        flag   "--git-name=",
               description: "Set the Git author/committer names to the given name."
        flag   "--git-email=",
               description: "Set the Git author/committer email to the given email."
        switch "--publish",
               description: "Publish the uploaded bottles."
        switch "--skip-online-checks",
               description: "Don't pass `--online` to `brew audit` and skip `brew livecheck`."
        switch "--skip-new",
               description: "Don't pass `--new` to `brew audit` for new formulae."
        switch "--skip-new-strict",
               depends_on:  "--skip-new",
               description: "Don't pass `--strict` to `brew audit` for new formulae."
        switch "--skip-dependents",
               description: "Don't test any dependents."
        switch "--skip-livecheck",
               description: "Don't test livecheck."
        switch "--skip-recursive-dependents",
               description: "Only test the direct dependents."
        switch "--skip-checksum-only-audit",
               description: "Don't audit checksum-only changes."
        switch "--skip-stable-version-audit",
               description: "Don't audit the stable version."
        switch "--skip-revision-audit",
               description: "Don't audit the revision."
        switch "--only-cleanup-before",
               description: "Only run the pre-cleanup step. Needs `--cleanup`, except in GitHub Actions."
        switch "--only-setup",
               description: "Only run the local system setup check step."
        switch "--only-tap-syntax",
               description: "Only run the tap syntax check step."
        switch "--stable",
               depends_on:  "--only-tap-syntax",
               description: "Only run the tap syntax checks needed on stable brew."
        switch "--only-formulae",
               description: "Only run the formulae steps."
        switch "--only-formulae-detect",
               description: "Only run the formulae detection steps."
        switch "--only-formulae-dependents",
               description: "Only run the formulae dependents steps."
        switch "--only-bottles-fetch",
               description: "Only run the bottles fetch steps. This optional post-upload test checks that all " \
                            "the bottles were uploaded correctly. It is not run unless requested and only needs " \
                            "to be run on a single machine. The bottle commit to be tested must be on the tested " \
                            "branch."
        switch "--only-cleanup-after",
               description: "Only run the post-cleanup step. Needs `--cleanup`, except in GitHub Actions."
        comma_array "--testing-formulae=",
                    description: "Use these testing formulae rather than running the formulae detection steps."
        comma_array "--added-formulae=",
                    description: "Use these added formulae rather than running the formulae detection steps."
        comma_array "--deleted-formulae=",
                    description: "Use these deleted formulae rather than running the formulae detection steps."
        comma_array "--skipped-or-failed-formulae=",
                    description: "Use these skipped or failed formulae from formulae steps for a " \
                                 "formulae dependents step."
        comma_array "--tested-formulae=",
                    description: "Use these tested formulae from formulae steps for a formulae dependents step."
        conflicts "--only-formulae-detect", "--testing-formulae"
        conflicts "--only-formulae-detect", "--added-formulae"
        conflicts "--only-formulae-detect", "--deleted-formulae"
        conflicts "--skip-dependents", "--only-formulae-dependents"
        conflicts "--only-cleanup-before", "--only-setup", "--only-tap-syntax",
                  "--only-formulae", "--only-formulae-detect", "--only-formulae-dependents",
                  "--only-cleanup-after", "--skip-setup"
      end

      sig { override.void }
      def run
        if GitHub::Actions.env_set?
          ENV["HOMEBREW_COLOR"] = "1"
          ENV["HOMEBREW_GITHUB_ACTIONS"] = "1"
        end
        ENV["HOMEBREW_TEST_BOT"] = "1"

        TestBot.run!(args)
      end
    end
  end
end
