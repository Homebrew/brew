# typed: strict
# frozen_string_literal: true

require "utils/analytics"
require "utils/output"

module Homebrew
  module TestBot
    class Test
      include Utils::Output::Mixin

      sig { returns(T::Array[Step]) }
      def failed_steps
        @steps.select(&:failed?)
      end

      sig { returns(T::Array[Step]) }
      def ignored_steps
        @steps.select(&:ignored?)
      end

      sig { returns(T::Array[Step]) }
      attr_reader :steps

      protected

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).returns(T::Boolean) }
      def cleanup?(args)
        Homebrew::TestBot.cleanup?(args)
      end

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).returns(T::Boolean) }
      def local?(args)
        Homebrew::TestBot.local?(args)
      end

      private

      sig { returns(T.nilable(Tap)) }
      attr_reader :tap

      sig { returns(T.nilable(String)) }
      attr_reader :git

      sig { returns(Pathname) }
      attr_reader :repository

      sig {
        params(
          tap:       T.nilable(Tap),
          git:       T.nilable(String),
          dry_run:   T::Boolean,
          fail_fast: T::Boolean,
          verbose:   T::Boolean,
        ).void
      }
      def initialize(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
        @tap = tap
        @git = git
        @dry_run = dry_run
        @fail_fast = fail_fast
        @verbose = verbose

        @steps = T.let([], T::Array[Step])

        tap_path = @tap ? @tap.path : CoreTap.instance.path
        @repository = T.let(tap_path, Pathname)
      end

      sig { params(klass: Symbol, method: T.nilable(T.any(String, Symbol))).void }
      def test_header(klass, method: "run!")
        puts
        puts Formatter.headline("Running #{klass}##{method}", color: :magenta)
      end

      sig { params(text: String).void }
      def info_header(text)
        puts Formatter.headline(text, color: :cyan)
      end

      sig {
        params(
          arguments:        String,
          named_args:       T.nilable(T.any(String, T::Array[String])),
          env:              T::Hash[String, String],
          verbose:          T::Boolean,
          ignore_failures:  T::Boolean,
          report_analytics: T::Boolean,
        ).returns(Step)
      }
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
