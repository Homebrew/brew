# typed: strict
# frozen_string_literal: true

require "cmd/--cache"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Cache do
  it_behaves_like "parseable arguments"

  it "prints all cache files for a given Formula" do
    expect { described_class.new(["--formula", (TEST_FIXTURE_DIR/"testball.rb").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--testball-}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints the cache files for a given Cask", :cask do
    expect { described_class.new(["--cask", cask_path("local-caffeine").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--caffeine\.zip}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints the cache files for a given Formula and Cask", :integration_test, :needs_macos do
    expect { brew "--cache", testball, cask_path("local-caffeine") }
      .to output(
        %r{
          #{HOMEBREW_CACHE}/downloads/[\da-f]{64}--testball-.*\n
          #{HOMEBREW_CACHE}/downloads/[\da-f]{64}--caffeine\.zip
        }xo,
      ).to_stdout
      .and output(/(Treating .* as a formula).*(Treating .* as a cask)/m).to_stderr
      .and be_a_success
  end
end
