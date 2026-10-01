# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/benchmark"

RSpec.describe Homebrew::DevCmd::Benchmark do
  it_behaves_like "parseable arguments"

  it "benchmarks a Formula", :integration_test do
    formula_file = setup_test_formula "testball"
    (HOMEBREW_PREFIX/"bin/brew").write <<~SH
      #!/bin/sh
      if [ "$1" = "--cache" ]; then
        printf '/tmp/testball-cache\n'
      fi
    SH
    (HOMEBREW_PREFIX/"bin/brew").chmod(0755)
    bin = mktmpdir
    (bin/"hyperfine").write <<~SH
      #!/bin/sh
      for argument in "$@"; do
        if [ "${previous:-}" = "--export-json" ]; then
          export_json=$argument
        fi
        previous=$argument
      done
      phase_output=$(printf '%s\n' "$export_json" | sed 's/hyperfine-/phases-/')
      printf '{"results":[{"mean":0.1}]}' > "$export_json"
      printf '{"events":[]}' > "$phase_output"
    SH
    (bin/"hyperfine").chmod(0755)

    mktmpdir do |directory|
      directory.cd do
        expect do
          brew "benchmark", "--runs=1", formula_file,
               "PATH" => "#{bin}:#{ENV.fetch("PATH")}"
        end
          .to output(/Benchmark results.*Full results written/m).to_stdout
          .and be_a_success
      end
      expect(directory/"benchmark/results.json").to be_a_file
    end
  end

  it "rotates workloads and records hyperfine and phase timings" do
    directory = mktmpdir
    hyperfine = mktmpdir/"hyperfine"
    hyperfine.write("#!/bin/sh\n")
    hyperfine.chmod(0755)
    formulae = Array.new(100) { |index| "formula-#{index + 1}" }
    benchmark = described_class.new(["--runs=2", *formulae])
    hyperfine_calls = []

    allow(benchmark).to receive_messages(
      which:          hyperfine,
      system_command: instance_double(SystemCommand::Result, stdout: ""),
    )
    allow(benchmark).to receive(:system_command!) do |executable, args:, **|
      if executable == hyperfine
        hyperfine_calls << args
        Pathname(args.fetch(args.index("--export-json") + 1))
          .write(JSON.generate("results" => [{ "mean" => 0.25 }]))
        command = Shellwords.split(args.last)
        timings_path = command.grep(/^HOMEBREW_PHASE_TIMINGS=/).fetch(0).delete_prefix("HOMEBREW_PHASE_TIMINGS=")
        Pathname(timings_path).write(JSON.generate("events" => [{ "phase" => "startup", "duration" => 250_000 }]))
        instance_double(SystemCommand::Result, stdout: "")
      elsif args.first(2) == ["--cache", "--formula"]
        instance_double(
          SystemCommand::Result,
          stdout: args.drop(2).map { |formula| "#{directory}/#{formula}.tar.gz" }.join("\n"),
        )
      else
        instance_double(SystemCommand::Result, stdout: "")
      end
    end

    Dir.chdir(directory) do
      expect { benchmark.run }
        .to output(/install\s+metadata cold\s+1\s+0\.250s\s+startup 250ms/).to_stdout
    end

    samples = JSON.parse((directory/"benchmark/results.json").read).fetch("samples")
    expect([
      hyperfine_calls.length,
      hyperfine_calls.all? { |args| args.each_cons(2).include?(["--warmup", "0"]) },
      samples.each_slice(16).map { |iteration| iteration.first.fetch("workload") },
      samples.map { |sample| sample.fetch("batch_size") }.uniq,
      samples.map { |sample| "#{sample.fetch("operation")}:#{sample.fetch("workload")}" }.uniq.sort,
      samples.first.slice("wall_time_seconds", "phase_totals_microseconds"),
    ]).to match([
      32,
      true,
      %w[metadata_cold archive_cold],
      [1, 10, 50, 100],
      ["fetch:archive_cold", "fetch:archive_warm", "fetch:metadata_cold", "install:archive_cold",
       "install:archive_warm", "install:fully_warm", "install:metadata_cold"],
      {
        "wall_time_seconds"         => 0.25,
        "phase_totals_microseconds" => hash_including("startup" => 250_000, "link" => 0),
      },
    ])
  end
end
