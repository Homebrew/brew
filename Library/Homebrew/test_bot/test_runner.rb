# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "test_bot/junit"
require "test_bot/test"
require "test_bot/test_cleanup"
require "test_bot/test_formulae"
require "test_bot/cleanup_after"
require "test_bot/cleanup_before"
require "test_bot/formulae_detect"
require "test_bot/formulae_dependents"
require "test_bot/bottles_fetch"
require "test_bot/formulae"
require "test_bot/setup"
require "test_bot/tap_syntax"

module Homebrew
  module TestBot
    module TestRunner
      module_function

      def ensure_blank_file_exists!(file)
        if file.exist?
          file.truncate(0)
        else
          FileUtils.touch(file)
        end
      end

      def run!(tap, git:, args:)
        tests = T.let([], T::Array[Test])
        skip_setup = args.skip_setup?
        skip_cleanup_before = T.let(false, T::Boolean)

        bottle_output_path = Pathname.new("bottle_output.txt")
        linkage_output_path = Pathname.new("linkage_output.txt")
        @skipped_or_failed_formulae_output_path = Pathname.new("skipped_or_failed_formulae-#{Utils::Bottles.tag}.txt")

        if no_only_args?(args) || args.only_formulae?
          ensure_blank_file_exists!(bottle_output_path)
          ensure_blank_file_exists!(linkage_output_path)
          ensure_blank_file_exists!(@skipped_or_failed_formulae_output_path)
        end

        output_paths = {
          bottle:                     bottle_output_path,
          linkage:                    linkage_output_path,
          skipped_or_failed_formulae: @skipped_or_failed_formulae_output_path,
        }

        test_bot_args = args.named.dup

        # With no arguments just build the most recent commit.
        test_bot_args << "HEAD" if test_bot_args.empty?

        test_bot_args.each do |argument|
          skip_cleanup_after = argument != test_bot_args.last
          current_tests = build_tests(argument, tap:,
                                                git:,
                                                output_paths:,
                                                skip_setup:,
                                                skip_cleanup_before:,
                                                skip_cleanup_after:,
                                                args:)
          skip_setup = true
          skip_cleanup_before = true
          tests += current_tests.values
          run_tests(current_tests, args:)
        end

        failed_steps = tests.map(&:failed_steps)
                            .flatten
                            .compact
        ignored_steps = tests.map(&:ignored_steps)
                             .flatten
                             .compact
        steps_output = if failed_steps.blank? && ignored_steps.blank?
          "All steps passed!"
        else
          output_lines = []

          if ignored_steps.present?
            output_lines += ["Warning: #{ignored_steps.count} failed step#{"s" if ignored_steps.count > 1} ignored!"]
            output_lines += ignored_steps.map(&:command_trimmed)
          end

          if failed_steps.present?
            output_lines += ["Error: #{failed_steps.count} failed step#{"s" if failed_steps.count > 1}!"]
            output_lines += failed_steps.map(&:command_trimmed)
          end

          output_lines.join("\n")
        end
        puts steps_output

        steps_output_path = Pathname.new("steps_output.txt")
        steps_output_path.unlink if steps_output_path.exist?
        steps_output_path.write(steps_output)

        if args.junit? && (no_only_args?(args) || args.only_formulae? || args.only_formulae_dependents?)
          junit_filters = %w[audit test]
          junit = Junit.new(tests)
          junit.build(filters: junit_filters)
          junit.write("brew-test-bot.xml")
        end

        failed_steps.empty?
      end

      def no_only_args?(args)
        any_only = args.only_cleanup_before? ||
                   args.only_setup? ||
                   args.only_tap_syntax? ||
                   args.only_formulae? ||
                   args.only_formulae_detect? ||
                   args.only_formulae_dependents? ||
                   args.only_bottles_fetch? ||
                   args.only_cleanup_after?
        !any_only
      end

      def build_tests(argument, tap:, git:, output_paths:, skip_setup:,
                      skip_cleanup_before:, skip_cleanup_after:, args:)
        tests = {}

        no_only_args = no_only_args?(args)

        if !skip_setup && (no_only_args || args.only_setup?)
          tests[:setup] = Setup.new(dry_run:   args.dry_run?,
                                    fail_fast: args.fail_fast?,
                                    verbose:   args.verbose?)
        end

        if no_only_args || args.only_tap_syntax?
          tests[:tap_syntax] = TapSyntax.new(tap:       tap || CoreTap.instance,
                                             dry_run:   args.dry_run?,
                                             git:,
                                             fail_fast: args.fail_fast?,
                                             verbose:   args.verbose?)
        end

        no_formulae_flags = args.testing_formulae.nil? &&
                            args.added_formulae.nil? &&
                            args.deleted_formulae.nil?
        if no_formulae_flags && (no_only_args || args.only_formulae? || args.only_formulae_detect?)
          tests[:formulae_detect] = FormulaeDetect.new(argument, tap:,
                                                                 git:,
                                                                 dry_run:   args.dry_run?,
                                                                 fail_fast: args.fail_fast?,
                                                                 verbose:   args.verbose?)
        end

        if no_only_args || args.only_formulae?
          tests[:formulae] = Formulae.new(tap:,
                                          git:,
                                          dry_run:      args.dry_run?,
                                          fail_fast:    args.fail_fast?,
                                          verbose:      args.verbose?,
                                          output_paths:)
        end

        if !args.skip_dependents? && (no_only_args || args.only_formulae? || args.only_formulae_dependents?)
          tests[:formulae_dependents] = FormulaeDependents.new(tap:,
                                                               git:,
                                                               dry_run:   args.dry_run?,
                                                               fail_fast: args.fail_fast?,
                                                               verbose:   args.verbose?)
        end

        if Homebrew::TestBot.cleanup?(args)
          if !skip_cleanup_before && (no_only_args || args.only_cleanup_before?)
            tests[:cleanup_before] = CleanupBefore.new(tap:,
                                                       git:,
                                                       dry_run:   args.dry_run?,
                                                       fail_fast: args.fail_fast?,
                                                       verbose:   args.verbose?)
          end

          if !skip_cleanup_after && (no_only_args || args.only_cleanup_after?)
            tests[:cleanup_after] = CleanupAfter.new(tap:,
                                                     git:,
                                                     dry_run:   args.dry_run?,
                                                     fail_fast: args.fail_fast?,
                                                     verbose:   args.verbose?)
          end
        end

        if args.only_bottles_fetch?
          tests[:bottles_fetch] = BottlesFetch.new(tap:,
                                                   git:,
                                                   dry_run:   args.dry_run?,
                                                   fail_fast: args.fail_fast?,
                                                   verbose:   args.verbose?)
        end

        tests
      end

      def run_tests(tests, args:)
        tests[:cleanup_before]&.run!(args:)
        begin
          tests[:setup]&.run!(args:)
          tests[:tap_syntax]&.run!(args:)

          testing_formulae, added_formulae, deleted_formulae = if (detect_test = tests[:formulae_detect])
            detect_test.run!(args:)

            [
              detect_test.testing_formulae,
              detect_test.added_formulae,
              detect_test.deleted_formulae,
            ]
          else
            [
              args.testing_formulae.to_a,
              args.added_formulae.to_a,
              args.deleted_formulae.to_a,
            ]
          end

          skipped_or_failed_formulae = if (formulae_test = tests[:formulae])
            formulae_test.testing_formulae = testing_formulae
            formulae_test.added_formulae = added_formulae
            formulae_test.deleted_formulae = deleted_formulae

            formulae_test.run!(args:)

            formulae_test.skipped_or_failed_formulae
          elsif args.skipped_or_failed_formulae.present?
            Array.new(args.skipped_or_failed_formulae)
          elsif @skipped_or_failed_formulae_output_path.exist?
            @skipped_or_failed_formulae_output_path.read.chomp.split(",")
          else
            []
          end

          if (dependents_test = tests[:formulae_dependents])
            dependents_test.testing_formulae = testing_formulae
            dependents_test.skipped_or_failed_formulae = skipped_or_failed_formulae
            dependents_test.tested_formulae = args.tested_formulae.to_a.presence || testing_formulae

            dependents_test.run!(args:)
          end

          if (fetch_test = tests[:bottles_fetch])
            fetch_test.testing_formulae = testing_formulae

            fetch_test.run!(args:)
          end
        ensure
          tests[:cleanup_after]&.run!(args:)
        end
      end
    end
  end
end
