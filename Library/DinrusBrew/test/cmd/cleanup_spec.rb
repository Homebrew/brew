# frozen_string_literal: true

require "cmd/cleanup"
require "cmd/shared_examples/args_parse"

RSpec.describe DinrusBrew::Cmd::CleanupCmd do
  before do
    FileUtils.mkdir_p DINRUSBREW_LIBRARY/"DinrusBrew/vendor/"
    FileUtils.touch DINRUSBREW_LIBRARY/"DinrusBrew/vendor/portable-ruby-version"
  end

  after do
    FileUtils.rm_rf DINRUSBREW_LIBRARY/"DinrusBrew"
  end

  it_behaves_like "parseable arguments"

  describe "--prune=all", :integration_test do
    it "removes all files in DinrusBrew's cache" do
      (DINRUSBREW_CACHE/"test").write "test"

      expect { brew "cleanup", "--prune=all" }
        .to output(%r{#{Regexp.escape(DINRUSBREW_CACHE)}/test}o).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end
end
