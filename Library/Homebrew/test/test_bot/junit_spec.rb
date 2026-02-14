# frozen_string_literal: true

require "dev-cmd/test-bot"

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

    it "includes failure element when a step did not pass" do
      start_time = Time.utc(2024, 1, 15, 12, 0, 0)
      step = instance_double(
        Homebrew::TestBot::Step,
        command_short: "test",
        status:        :failed,
        time:          2.0,
        start_time:    start_time,
        passed?:       false,
        command:       ["brew", "test", "foo"],
      )
      test = instance_double(Homebrew::TestBot::Test, steps: [step])

      junit = described_class.new([test])
      junit.build(filters: ["test"])

      Dir.mktmpdir do |tmpdir|
        path = "#{tmpdir}/junit.xml"
        junit.write(path)

        content = File.read(path)
        expect(content).to include("<failure ")
        expect(content).to include("failed")
      end
    end
  end
end
