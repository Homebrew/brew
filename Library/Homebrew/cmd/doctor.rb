# typed: strict
# frozen_string_literal: true

require "utils/profiling"

require "abstract_command"
require "diagnostic"
require "diagnostic/finding"
require "cask/caskroom"
require "json"

module Homebrew
  module Cmd
    class Doctor < AbstractCommand
      cmd_args do
        description <<~EOS
          Check your system for potential problems. Will exit with a non-zero status
          if any potential problems are found.

          Please note that these warnings are just used to help the Homebrew maintainers
          with debugging if you file an issue. If everything you use Homebrew for
          is working fine: please don't worry or file an issue; just ignore this.
        EOS
        switch "--list-checks",
               description: "List all audit methods, which can be run individually " \
                            "if provided as arguments."
        switch "--json",
               description: "Print a JSON representation.",
               hidden:      true
        switch "-D", "--audit-debug",
               description: "Enable debugging and profiling of audit methods."

        named_args :diagnostic_check
      end

      sig { override.void }
      def run
        Utils::Profiling.inject_stats!(Diagnostic::Checks, /^check_*/) if args.audit_debug?

        checks = Diagnostic::Checks.new(verbose: args.verbose?)

        if args.list_checks?
          puts checks.all
          return
        end

        if args.no_named?
          slow_checks = %w[
            check_for_broken_symlinks
            check_missing_deps
          ]
          methods = (checks.all - slow_checks) + slow_checks
          methods -= checks.cask_checks unless Cask::Caskroom.any_casks_installed?
        else
          methods = args.named
        end

        finding_collection = []
        first_warning = T.let(true, T::Boolean)
        methods.each do |method|
          $stderr.puts Formatter.headline("Checking #{method}", color: :magenta) if args.debug?
          unless checks.respond_to?(method)
            ofail "No check available by the name: #{method}"
            next
          end

          finding         = checks.public_send(method)
          method_findings = T.let(Array(finding).compact, T::Array[Diagnostic::Finding])
          next if method_findings.empty?

          finding_collection.concat(method_findings.compact)
          Homebrew.failed = true
          next if args.json?

          if first_warning && !args.quiet?
            $stderr.puts <<~EOS
              #{Tty.bold}Please note that these warnings are just used to help the Homebrew maintainers
              with debugging if you file an issue. If everything you use Homebrew for is
              working fine: please don't worry or file an issue; just ignore this. Thanks!#{Tty.reset}
            EOS
          end

          $stderr.puts
          opoo method_findings.each(&:to_s).join("\n")
          first_warning = false
        end

        finding_maps = finding_collection.map(&:to_h)
        tier = Diagnostic::Finding.support_tier(finding_collection.map(&:tier))
        if args.json?
          puts JSON.pretty_generate({ tier:, findings: finding_maps }).gsub(/\[\n\n\s*\]/, "[]")

          return
        end

        return if args.quiet?

        if Homebrew.failed?
          puts Diagnostic::Finding.support_tier_message(tier:)
        else
          puts "Your system is ready to brew."
        end
      end
    end
  end
end
