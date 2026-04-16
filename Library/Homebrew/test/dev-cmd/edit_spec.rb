# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/edit"

RSpec.describe Homebrew::DevCmd::Edit do
  it_behaves_like "parseable arguments"

  it "opens a given Formula in an editor", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    setup_test_formula "testball"

    expect { brew "edit", "testball", "HOMEBREW_EDITOR" => "/bin/cat", "HOMEBREW_NO_ENV_HINTS" => "1" }
      .to output(/# something here/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "auto-taps core when editing an API-known formula without the tap installed" do
    (HOMEBREW_REPOSITORY/".git").mkpath

    allow(CoreTap.instance).to receive(:installed?).and_return(false)

    require "api"
    allow(Homebrew::API).to receive(:formula_names).and_return(["testball"])
    allow(Homebrew::API::Formula).to receive(:all_formulae).and_return("testball" => {})

    expect(CoreTap.instance).to receive(:install).with(force: true) do
      allow(CoreTap.instance).to receive(:installed?).and_return(true)
      CoreTap.instance.clear_cache

      formula_path = CoreTap.instance.path/"Formula"/"testball.rb"
      formula_path.dirname.mkpath
      formula_path.write <<~RUBY
        class Testball < Formula
          url "https://brew.sh/testball-1.0"
        end
      RUBY
    end

    allow_any_instance_of(described_class).to receive(:exec_editor)

    described_class.new(["testball"]).run
  end
end
