# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew prof" do
  it_behaves_like "parseable arguments"

  describe "integration tests", :integration_test, :needs_network do
    after do
      FileUtils.rm_rf HOMEBREW_LIBRARY_PATH/"prof"
    end

    it "works using ruby-prof (the default)" do
      expect { brew "prof", "help", "HOMEBREW_BROWSER" => "echo" }
        .to output(/^Example usage:/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    it "works using stackprof" do
      expect { brew "prof", "--stackprof", "help", "HOMEBREW_BROWSER" => "echo" }
        .to output(/^Example usage:/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end
end
