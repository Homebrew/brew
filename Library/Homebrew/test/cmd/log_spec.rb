# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew log" do
  it_behaves_like "parseable arguments"

  it "shows the Git log for a given Formula", :integration_test do
    setup_test_formula "testball"

    core_tap = CoreTap.new
    core_tap.path.cd do
      system "git", "init"
      system "git", "add", "--all"
      system "git", "commit", "-m", "This is a test commit for Testball"
    end

    core_tap_url = "file://#{core_tap.path}"
    shallow_tap = Tap.fetch("homebrew", "shallow")

    system "git", "clone", "--depth=1", core_tap_url, shallow_tap.path

    expect { brew "log", "#{shallow_tap}/testball" }
      .to output(/This is a test commit for Testball/).to_stdout
      .and output(%r{Warning: homebrew/shallow is a shallow clone}).to_stderr
      .and be_a_success

    expect(shallow_tap.path/".git/shallow").to exist, "A shallow clone should have been created."
  end
end
