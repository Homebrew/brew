# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/analytics"
require "utils/output"

module Homebrew
  module TestBot
    class Test
      include Utils::Output::Mixin

      def failed_steps
        @steps.select(&:failed?)
      end

      def ignored_steps
        @steps.select(&:ignored?)
      end

      attr_reader :steps

      protected

      def cleanup?(args)
        Homebrew::TestBot.cleanup?(args)
      end

      def local?(args)
        Homebrew::TestBot.local?(args)
      end

      private

      attr_reader :tap, :git, :repository

      def initialize(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
        @tap = tap
        @git = git
        @dry_run = dry_run
        @fail_fast = fail_fast
        @verbose = verbose

        @steps = []

        @repository = if @tap
          @tap.path
        else
          CoreTap.instance.path
        end
      end

      def test_header(klass, method: "run!")
        puts
        puts Formatter.headline("Running #{klass}##{method}", color: :magenta)
      end

      def info_header(text)
        puts Formatter.headline(text, color: :cyan)
      end

      def test(*arguments, named_args: nil, env: {}, verbose: @verbose, ignore_failures: false,
               report_analytics: false)
        step = Step.new(
          arguments,
          named_args:,
          env:,
          verbose:,
          ignore_failures:,
          repository:      @repository,
        )
        step.run(dry_run: @dry_run, fail_fast: @fail_fast)
        @steps << step

        if ENV["HOMEBREW_TEST_BOT_ANALYTICS"].present? && report_analytics
          ::Utils::Analytics.report_test_bot_test(step.command_short, step.passed?)
        end

        step
      end
    end
  end
end
