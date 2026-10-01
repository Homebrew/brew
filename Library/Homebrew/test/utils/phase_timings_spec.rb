# typed: true
# frozen_string_literal: true

require "utils/phase_timings"

RSpec.describe Homebrew::PhaseTimings do
  let(:output_path) { HOMEBREW_TEMP/"phase-timings.json" }

  after { output_path.unlink if output_path.exist? }

  it "writes machine-readable phase events" do
    described_class.start!(
      output_path:,
      started_at:  Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f,
      command:     ["install", "foo"],
    )

    expect(described_class.measure("checksum", detail: "foo") { :result }).to eq(:result)
    described_class.write!

    timings = JSON.parse(output_path.read)
    expect(timings).to include(
      "schema_version" => 1,
      "time_unit"      => "microseconds",
      "command"        => ["install", "foo"],
    )
    expect(timings.fetch("events")).to include(
      hash_including(
        "phase"     => "checksum",
        "detail"    => "foo",
        "start"     => be_a(Integer),
        "duration"  => be_a(Integer),
        "thread_id" => be_a(Integer),
      ),
    )
  end
end
