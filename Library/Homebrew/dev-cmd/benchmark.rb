# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "json"
require "shellwords"
require "system_command"
require "time"
require "tmpdir"

module Homebrew
  module DevCmd
    class Benchmark < AbstractCommand
      include SystemCommand::Mixin

      PHASES = %w[
        startup cli_parse command_load api_metadata_load formula_inflation dependency_resolution
        download_enqueue curl_headers curl_body checksum pour link
      ].freeze
      BENCHMARK_ENV = T.let({
        "HOMEBREW_NO_ANALYTICS"                  => "1",
        "HOMEBREW_NO_AUTO_UPDATE"                => "1",
        "HOMEBREW_NO_AUTOREMOVE"                 => "1",
        "HOMEBREW_NO_ENV_HINTS"                  => "1",
        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" => "1",
        "HOMEBREW_NO_INSTALL_CLEANUP"            => "1",
      }.freeze, T::Hash[String, String])

      class Scenario < T::Struct
        const :operation, String
        const :workload, String
        const :formulae, T::Array[String]
      end

      class Sample < T::Struct
        const :iteration, Integer
        const :operation, String
        const :workload, String
        const :batch_size, Integer
        const :wall_time_seconds, Float
        const :phase_totals_microseconds, T::Hash[String, Integer]
      end

      cmd_args do
        description <<~EOS
          Benchmark this `brew` with `hyperfine`, installing `hyperfine` first if it is
          missing. Each of the metadata-cold, archive-cold, archive-warm and fully-warm
          `brew install` workloads is measured separately, as are the metadata-cold,
          archive-cold and archive-warm `brew fetch` workloads for each of 1, 10, 50 and
          100 <formula>e that are available: pass 100 <formula>e for full coverage and
          fewer for a shorter run.

          The first <formula> is used for the install workloads: its dependencies are
          installed once up front and left behind. All <formula>e must initially be
          uninstalled and the archive-cold workloads re-download every bottle in the
          batch. Mean wall times and `$HOMEBREW_PHASE_TIMINGS` phase totals are printed
          and written to `benchmark/results.json`.
        EOS
        switch "--exec",
               description: "Run `hyperfine` with the arguments given after `--` instead of " \
                            "Homebrew's own workloads, e.g. `brew benchmark --exec -- 'brew --version'`."
        flag "--runs=",
             description: "Number of repetitions of each workload. Defaults to 3."

        conflicts "--exec", "--runs"

        named_args :formula, min: 1
      end

      sig { override.void }
      def run
        # Resolve `hyperfine` before any workload is prepared: installing it later
        # would refill the API metadata a cold workload has just removed.
        hyperfine = which("hyperfine", ENV.fetch("HOMEBREW_PATH")) || (HOMEBREW_PREFIX/"bin/hyperfine")
        unless hyperfine.executable?
          ohai "Installing hyperfine..."
          SystemCommand.safe_system HOMEBREW_BREW_FILE, "install", "--formula", "hyperfine", env: BENCHMARK_ENV
          # An already-installed but unlinked `hyperfine` makes the install a no-op.
          raise "`#{hyperfine}` is missing: try `brew link hyperfine`." unless hyperfine.executable?
        end
        exec(hyperfine.to_s, *args.named) if args.exec?

        runs = args.runs || "3"
        raise UsageError, "`--runs` must be a positive integer." unless runs.match?(/\A[1-9]\d*\z/)

        formulae = args.named
        install_formula = formulae.fetch(0)
        installed = system_command(
          HOMEBREW_BREW_FILE,
          args:         ["list", "--versions", "--formula", *formulae],
          env:          BENCHMARK_ENV,
          print_stderr: false,
        ).stdout.lines(chomp: true)
        raise UsageError, "Formulae must be uninstalled: #{installed.join(", ")}" if installed.any?

        brew!("install", "--only-dependencies", "--formula", install_formula)

        scenarios = [
          *%w[metadata_cold archive_cold archive_warm fully_warm].map do |workload|
            Scenario.new(operation: "install", workload:, formulae: formulae.first(1))
          end,
          *%w[metadata_cold archive_cold archive_warm]
            .product([1, 10, 50, 100].select { |batch_size| batch_size <= formulae.length })
            .map do |workload, batch_size|
              Scenario.new(operation: "fetch", workload:, formulae: formulae.first(batch_size))
            end,
        ]
        samples = T.let([], T::Array[Sample])

        begin
          Dir.mktmpdir("brew-benchmark") do |temporary_directory|
            runs.to_i.times do |iteration|
              # Machines drift by tens of milliseconds over a run, so rotate rather
              # than repeat the order: every workload is then measured from several
              # positions instead of always the same one.
              scenarios.rotate(iteration).each do |scenario|
                ohai "#{scenario.workload.tr("_", " ")} #{scenario.operation}",
                     "run #{iteration + 1}, #{scenario.formulae.length} formulae"
                prepare(scenario, install_formula)
                samples << measure(hyperfine, scenario, iteration + 1, samples.length + 1,
                                   Pathname(temporary_directory))
              end
            end
          end
        ensure
          remove_formula(install_formula)
        end

        output = Pathname("benchmark/results.json").expand_path
        output.dirname.mkpath
        output.write("#{JSON.pretty_generate({
          "schema_version" => 1,
          "generated_at"   => Time.now.utc.iso8601,
          "brew_version"   => HOMEBREW_VERSION,
          "runs"           => runs.to_i,
          "formulae"       => formulae,
          "phases"         => PHASES,
          "samples"        => samples.map(&:serialize),
        })}\n")
        summarise(samples)
        ohai "Full results written to #{output}"
      end

      private

      sig { params(scenario: Scenario, install_formula: String).void }
      def prepare(scenario, install_formula)
        if scenario.workload == "fully_warm"
          brew!(*command_args(scenario))
          return
        end

        remove_formula(install_formula)
        case scenario.workload
        when "metadata_cold"
          brew!("fetch", "--formula", *scenario.formulae)
          FileUtils.rm_rf HOMEBREW_CACHE/"api"
        when "archive_cold"
          # `brew --cache` resolves each formula through the API, so this warms the
          # metadata a preceding metadata-cold workload removed as well as naming
          # the archives to delete. Warming with `brew fetch` instead would download
          # every bottle in the batch twice.
          FileUtils.rm_f brew!("--cache", "--formula", *scenario.formulae).lines(chomp: true)
        when "archive_warm"
          brew!("fetch", "--formula", *scenario.formulae)
        end
      end

      sig {
        params(
          hyperfine:           Pathname,
          scenario:            Scenario,
          iteration:           Integer,
          sequence:            Integer,
          temporary_directory: Pathname,
        ).returns(Sample)
      }
      def measure(hyperfine, scenario, iteration, sequence, temporary_directory)
        hyperfine_output = temporary_directory/"hyperfine-#{sequence}.json"
        phase_output = temporary_directory/"phases-#{sequence}.json"
        system_command!(
          hyperfine,
          args:         [
            "--warmup", "0",
            "--runs", "1",
            "--export-json", hyperfine_output,
            "--command-name", "#{scenario.operation}:#{scenario.workload}:#{scenario.formulae.length}",
            Shellwords.join([
              "/usr/bin/env",
              *BENCHMARK_ENV.map { |key, value| "#{key}=#{value}" },
              "HOMEBREW_PHASE_TIMINGS=#{phase_output}",
              HOMEBREW_BREW_FILE.to_s,
              *command_args(scenario),
            ])
          ],
          print_stdout: true,
        )

        phase_totals = PHASES.to_h { |phase| [phase, 0] }
        JSON.parse(phase_output.read).fetch("events").each do |event|
          phase = event.fetch("phase")
          phase_totals[phase] = phase_totals.fetch(phase, 0) + event.fetch("duration")
        end

        Sample.new(
          iteration:,
          operation:                 scenario.operation,
          workload:                  scenario.workload,
          batch_size:                scenario.formulae.length,
          wall_time_seconds:         JSON.parse(hyperfine_output.read).fetch("results").fetch(0).fetch("mean"),
          phase_totals_microseconds: phase_totals,
        )
      end

      sig { params(samples: T::Array[Sample]).void }
      def summarise(samples)
        ohai "Benchmark results"
        puts "#{"operation".ljust(10)}#{"workload".ljust(15)}#{"batch".rjust(5)}#{"wall".rjust(10)}  slowest phases"
        samples.group_by { |sample| [sample.operation, sample.workload, sample.batch_size] }
               .each do |(operation, workload, batch_size), workload_samples|
          means = PHASES.union(workload_samples.flat_map { |sample| sample.phase_totals_microseconds.keys })
                        .to_h do |phase|
            [phase, workload_samples.sum { |sample| sample.phase_totals_microseconds.fetch(phase, 0) } /
              workload_samples.length]
          end
          slowest = means.reject { |_, total| total.zero? }
                         .max_by(3) { |_, total| total }
                         .map { |phase, total| "#{phase} #{total / 1000}ms" }
          wall = workload_samples.sum(&:wall_time_seconds) / workload_samples.length
          puts "#{operation.ljust(10)}#{workload.tr("_", " ").ljust(15)}#{batch_size.to_s.rjust(5)}" \
               "#{format("%.3fs", wall).rjust(10)}  #{slowest.join(", ")}"
        end
      end

      sig { params(scenario: Scenario).returns(T::Array[String]) }
      def command_args(scenario) = [scenario.operation, "--formula", *scenario.formulae]

      sig { params(args: String).returns(String) }
      def brew!(*args) = system_command!(HOMEBREW_BREW_FILE, args:, env: BENCHMARK_ENV, print_stderr: false).stdout

      sig { params(formula: String).void }
      def remove_formula(formula)
        brew!("uninstall", "--force", "--ignore-dependencies", "--formula", formula)
      end
    end
  end
end
