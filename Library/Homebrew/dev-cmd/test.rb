# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "extend/ENV"
require "sandbox"
require "timeout"

module Homebrew
  module DevCmd
    class Test < AbstractCommand
      cmd_args do
        description <<~EOS
          Run the test method provided by an installed formula.
          There is no standard output or return code, but generally it should notify the
          user if something is wrong with the installed formula.

          *Example:* `brew install jruby && brew test jruby`
        EOS
        switch "-f", "--force",
               description: "Test formulae even if they are unlinked."
        switch "--HEAD",
               description: "Test the HEAD version of a formula."
        switch "--keep-tmp",
               description: "Retain the temporary files created for the test."
        switch "--retry",
               description: "Retry if a testing fails."

        named_args :installed_formula, min: 1, without_api: true
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["formula_test"], setup_path: false)

        require "formula_assertions"
        require "formula_free_port"
        require "utils/fork"

        args.named.to_resolved_formulae.each do |f|
          # Cannot test uninstalled formulae
          unless f.latest_version_installed?
            ofail "Testing requires the latest version of #{f.full_name}"
            next
          end

          # Cannot test formulae without a test method
          unless f.test_defined?
            ofail "#{f.full_name} defines no test"
            next
          end

          # Don't test unlinked formulae
          if !args.force? && !f.keg_only? && !f.linked?
            ofail "#{f.full_name} is not linked"
            next
          end

          # Don't test formulae missing test dependencies
          missing_test_deps = f.recursive_dependencies do |dependent, dependency|
            Dependency.prune if dependency.installed?
            next if dependency.test? && dependent == f

            Dependency.prune unless dependency.required?
          end.map(&:to_s)
          unless missing_test_deps.empty?
            ofail "#{f.full_name} is missing test dependencies: #{missing_test_deps.join(" ")}"
            next
          end

          oh1 "Testing #{f.full_name}"

          env = ENV.to_hash

          begin
            exec_args = HOMEBREW_RUBY_EXEC_ARGS + %W[
              --
              #{HOMEBREW_LIBRARY_PATH}/test.rb
              #{f.path}
            ].concat(args.options_only)

            exec_args << "--HEAD" if f.head?

            if Sandbox.available?
              sandbox = Sandbox.new
              f.logs.mkpath
              sandbox.record_log(f.logs/"test.sandbox.log")
              sandbox.allow_write_temp_and_cache
              sandbox.allow_write_log(f)
              sandbox.allow_write_xcode
              sandbox.allow_write_path(HOMEBREW_PREFIX/"var/cache")
              sandbox.allow_write_path(HOMEBREW_PREFIX/"var/homebrew/locks")
              sandbox.allow_write_path(HOMEBREW_PREFIX/"var/log")
              sandbox.allow_write_path(HOMEBREW_PREFIX/"var/run")
              sandbox.deny_all_network unless f.class.network_access_allowed?(:test)
              sandbox.run(*exec_args)
            else
              Utils.safe_fork do
                exec(*exec_args)
              end
            end
          # Rescue any possible exception types.
          rescue Exception => e # rubocop:disable Lint/RescueException
            retry if retry_test?(f)

            require "utils/backtrace"
            ofail "#{f.full_name}: failed"
            $stderr.puts e, Utils::Backtrace.clean(e)
          ensure
            ENV.replace(env)
          end
        end
      end

      private

      sig { params(formula: Formula).returns(T::Boolean) }
      def retry_test?(formula)
        @test_failed ||= T.let(Set.new, T.nilable(T::Set[T.untyped]))
        if args.retry? && @test_failed.add?(formula)
          oh1 "Testing #{formula.full_name} (again)"
          formula.clear_cache
          ENV["RUST_BACKTRACE"] = "full"
          true
        else
          Homebrew.failed = true
          false
        end
      end
    end
  end
end
