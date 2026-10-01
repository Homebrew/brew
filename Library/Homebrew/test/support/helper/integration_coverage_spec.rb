# typed: strict
# frozen_string_literal: true

require "test/support/helper/integration_coverage"

RSpec.describe Homebrew::TestIntegrationCoverage do
  it "records coverage before an integration command execs" do
    mktmpdir do |directory|
      env = {
        "HOMEBREW_INTEGRATION_COVERAGE_DIR" => directory.to_s,
        "HOMEBREW_INTEGRATION_TEST"         => "integration-command",
        "HOMEBREW_TESTS_COVERAGE"           => "1",
      }
      coverage_helper = HOMEBREW_LIBRARY_PATH/"test/support/helper/integration_coverage"
      integration_mocks = HOMEBREW_LIBRARY_PATH/"test/support/helper/integration_mocks"
      script = "abort if defined?(SimpleCov); Object.new.extend(Homebrew).exec('/usr/bin/true')"

      _, _, status = Open3.capture3(
        env,
        *HOMEBREW_RUBY_EXEC_ARGS,
        "-r#{coverage_helper}",
        "-r#{integration_mocks}",
        "-e", script
      )
      result_path = directory/"integration-command.json"
      coverage = result_path.exist? ? JSON.parse(result_path.read) : {}

      expect([status.success?, coverage.key?(integration_mocks.sub_ext(".rb").to_s)]).to eq([true, true])
    end
  end

  it "merges child results before storing them with SimpleCov" do
    require "simplecov"

    mktmpdir do |directory|
      source = (HOMEBREW_LIBRARY_PATH/"brew.rb").to_s
      branches = {
        [:if, 0, 1, 0, 1, 1] => {
          [:then, 1, 1, 0, 1, 1] => 1,
        },
      }
      File.write(directory/"one.json", JSON.generate(source => { lines: [1], branches: }))
      File.write(directory/"two.json", JSON.generate(source => { lines: [2], branches: }))
      stored_results = []
      allow(SimpleCov::ResultMerger).to receive(:store_result) { |result| stored_results << result }

      described_class.store_results!(directory)

      stored_result = stored_results.fetch(0)
      coverage = stored_result.original_result.fetch(source)
      expect([coverage.fetch("lines"), coverage.fetch("branches").values.first.values])
        .to eq([[3], [2]])
    end
  end
end
