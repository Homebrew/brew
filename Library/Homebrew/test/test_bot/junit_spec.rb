# typed: strict
# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::Junit do
  # Regression test: Junit requires REXML before use. Without the require calls in #initialize,
  # environments that don't load REXML elsewhere (e.g. Linux CI) raise
  # "uninitialized constant Homebrew::TestBot::Junit::REXML".
  describe "#initialize and #build and #write" do
    it "loads REXML and produces valid JUnit XML without NameError" do
      start_time = Time.utc(2024, 1, 15, 12, 0, 0)
      step = instance_double(
        Homebrew::TestBot::Step,
        command_short: "audit",
        status:        :passed,
        time:          1.5,
        start_time:    start_time,
        passed?:       true,
        command:       ["brew", "audit", "foo"],
      )
      test = instance_double(Homebrew::TestBot::Test, steps: [step])

      junit = described_class.new([test])
      junit.build(filters: ["audit"])

      Dir.mktmpdir do |tmpdir|
        path = "#{tmpdir}/junit.xml"
        junit.write(path)

        expect(File).to exist(path)
        content = File.read(path)
        expect(content).to include("<?xml")
        expect(content).to include("testsuites")
        expect(content).to include("testcase")
        expect(content).to include("name='audit'")
      end
    end

    it "reports failed steps as failures and ignored steps as skipped" do
      start_time = Time.utc(2024, 1, 15, 12, 0, 0)
      steps = [:failed, :ignored].map do |status|
        instance_double(Homebrew::TestBot::Step, command_short: "test", status:, time: 2.0, start_time:,
                        passed?: false, ignored?: status == :ignored, command: %w[brew test foo])
      end
      test = instance_double(Homebrew::TestBot::Test, steps:)

      junit = described_class.new([test])
      junit.build(filters: ["test"])

      Dir.mktmpdir do |tmpdir|
        path = "#{tmpdir}/junit.xml"
        junit.write(path)

        expect(REXML::XPath.match(REXML::Document.new(File.read(path)), "//testcase/*").map(&:name))
          .to eq(%w[failure skipped])
      end
    end
  end
end
