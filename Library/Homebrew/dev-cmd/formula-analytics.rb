# typed: strict
# frozen_string_literal: true

require "utils/analytics/influx"

require "abstract_command"

module Homebrew
  module DevCmd
    class FormulaAnalytics < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `formula-analytics`

          Query Homebrew's analytics.
        EOS
        flag   "--days-ago=",
               description: "Query from the specified days ago until the present. The default is 30 days."
        switch "--install",
               description: "Output the number of specifically requested installations or installation as " \
                            "dependencies of formulae. This is the default."
        switch "--install-on-request",
               description: "Output the number of specifically requested installations of formulae."
        switch "--cask-install",
               description: "Output the number of installations of casks."
        switch "--build-error",
               description: "Output the number of build errors for formulae."
        switch "--os-version",
               description: "Output the number of events by OS name and version."
        switch "--homebrew-devcmdrun-developer",
               description: "Output the number of devcmdrun/HOMEBREW_DEVELOPER events."
        switch "--homebrew-env-config",
               description: "Output rates of non-default Homebrew environment configuration variables."
        switch "--homebrew-os-arch-level-ci",
               description: "Output the number of OS/Architecture/Architecture level/CI events."
        switch "--homebrew-os-arch-ci",
               description: "Output the number of OS/Architecture/CI events."
        switch "--homebrew-prefixes",
               description: "Output Homebrew prefixes."
        switch "--homebrew-versions",
               description: "Output Homebrew versions."
        switch "--brew-command-run",
               description: "Output `brew` commands run."
        switch "--brew-command-run-options",
               description: "Output `brew` commands run with options."
        switch "--brew-test-bot-test",
               description: "Output `brew test-bot` steps run."
        switch "--json",
               description: "Output JSON. This is required: plain text support has been removed."
        switch "--all-core-formulae-json",
               description: "Output a different JSON format containing the JSON data for all " \
                            "Homebrew/homebrew-core formulae."
        switch "--setup",
               description: "Install the necessary Python dependencies and exit without running a query."

        conflicts "--install", "--cask-install", "--install-on-request", "--build-error", "--os-version",
                  "--homebrew-devcmdrun-developer", "--homebrew-env-config", "--homebrew-os-arch-ci",
                  "--homebrew-os-arch-level-ci", "--homebrew-prefixes", "--homebrew-versions", "--brew-command-run",
                  "--brew-command-run-options", "--brew-test-bot-test"
        conflicts "--json", "--all-core-formulae-json", "--setup"

        named_args :none

        hide_from_man_page!
      end

      sig { override.void }
      def run
        influx = Utils::Analytics::Influx.new
        influx.setup_python
        if args.setup?
          SystemCommand.safe_system influx.venv_python, influx.influxdb_query_script, "--check"
          return
        end

        categories = []
        categories << :build_error if args.build_error?
        categories << :cask_install if args.cask_install?
        categories << :formula_install if args.install?
        categories << :formula_install_on_request if args.install_on_request?
        categories << :homebrew_devcmdrun_developer if args.homebrew_devcmdrun_developer?
        categories << :homebrew_env_config if args.homebrew_env_config?
        categories << :homebrew_os_arch_ci if args.homebrew_os_arch_ci?
        categories << :homebrew_os_arch_level_ci if args.homebrew_os_arch_level_ci?
        categories << :homebrew_prefixes if args.homebrew_prefixes?
        categories << :homebrew_versions if args.homebrew_versions?
        categories << :os_versions if args.os_version?
        categories << :command_run if args.brew_command_run?
        categories << :command_run_options if args.brew_command_run_options?
        categories << :test_bot_test if args.brew_test_bot_test?

        influx.query(categories:, days_ago: (args.days_ago || 30).to_i,
                     all_core_formulae_json: args.all_core_formulae_json?).each do |json|
          puts JSON.pretty_generate(json)
        end
      end
    end
  end
end
