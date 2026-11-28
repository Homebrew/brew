# typed: strict
# frozen_string_literal: true

require "cask/ci/runner_matrix"
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

      sig {
        params(
          arguments:        T.any(String, Pathname),
          named_args:       T.nilable(T.any(String, T::Array[String])),
          env:              T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
          verbose:          T::Boolean,
          ignore_failures:  T::Boolean,
          report_analytics: T::Boolean,
          dry_run:          T::Boolean,
          block:            T.nilable(T.proc.void),
        ).returns(Step)
      }
      def test(*arguments, named_args: nil, env: {}, verbose: @verbose, ignore_failures: false,
               report_analytics: false, dry_run: @dry_run, &block)
        step = Step.new(
          arguments.map(&:to_s),
          named_args:,
          env:,
          verbose:,
          ignore_failures:,
          repository:      @repository,
        )
        @steps << step
        step.run(dry_run:, fail_fast: @fail_fast, &block)

        if ENV["HOMEBREW_TEST_BOT_ANALYTICS"].present? && report_analytics
          ::Utils::Analytics.report_test_bot_test(step.command_short, step.passed?)
        end

        step
      end

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

      sig { params(type: Symbol, name: String, args: Homebrew::Cmd::TestBotCmd::Args).returns(Step) }
      def fetch(type, name, args:)
        command = ["brew", "fetch", "--#{type}", "--retry", name]
        command.push("--test", "--build-bottle") if type == :formula
        command << "--force" if cleanup?(args)
        test(*command)
      end

      sig {
        params(type: Symbol, name: String, args: Homebrew::Cmd::TestBotCmd::Args, new_package: T::Boolean,
               online: T::Boolean).returns(T::Array[String])
      }
      def audit_command(type, name, args:, new_package:, online: !args.skip_online_checks?)
        command = ["brew", "audit", "--#{type}", name]
        command << "--online" if online
        exceptions = args.except.to_a.dup
        if new_package
          if !args.skip_new? && !args.skip_online_checks?
            command << "--new"
          elsif !args.skip_new_strict?
            command << "--strict"
          end
        elsif type == :formula
          command << "--git" << "--skip-style"
          exceptions << "unconfirmed_checksum_change" if args.skip_checksum_only_audit?
          exceptions << "stable_version" if args.skip_stable_version_audit?
          exceptions << "revision" if args.skip_revision_audit?
        end
        exceptions.concat(Cask::CI::RunnerMatrix::LIVECHECK_AUDITS) if type == :cask && args.skip_livecheck?
        command << "--except=#{exceptions.uniq.join(",")}" if exceptions.present?
        command
      end

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
    end
  end
end
