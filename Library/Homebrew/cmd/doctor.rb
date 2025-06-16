# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "diagnostic"
require "cask/caskroom"

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
        switch "-D", "--audit-debug",
               description: "Enable debugging and profiling of audit methods."

        named_args :diagnostic_check
      end

      sig { override.void }
      def run
        Homebrew.inject_dump_stats!(Diagnostic::Checks, /^check_*/) if args.audit_debug?

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

        first_warning = T.let(true, T::Boolean)
        methods.each do |method|
          $stderr.puts Formatter.headline("Checking #{method}", color: :magenta) if args.debug?
          unless checks.respond_to?(method)
            ofail "No check available by the name: #{method}"
            next
          end

          out = checks.send(method)
          next if out.blank?

          if first_warning
            $stderr.puts <<~EOS
              #{Tty.bold}Please note that these warnings are just used to help the Homebrew maintainers
              with debugging if you file an issue. If everything you use Homebrew for is
              working fine: please don't worry or file an issue; just ignore this. Thanks!#{Tty.reset}
            EOS
          end

          $stderr.puts
          opoo out
          Homebrew.failed = true
          first_warning = false
        end

        puts "Your system is ready to brew." if !Homebrew.failed? && !args.quiet?
      end
    end
  end
end
