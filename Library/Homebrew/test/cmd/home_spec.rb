# frozen_string_literal: true

require "cmd/home"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Home do
  let(:testballhome_homepage) do
    Formula["testballhome"].homepage
  end

  let(:local_caffeine_path) do
    cask_path("local-caffeine")
  end

  let(:local_caffeine_homepage) do
    Cask::CaskLoader.load(local_caffeine_path).homepage
  end

  it_behaves_like "parseable arguments"

  it "opens the project page when no formula or cask is specified", :integration_test do
    expect { brew "home", "HOMEBREW_BROWSER" => "echo" }
      .to output("https://brew.sh\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "opens the homepage for a given Formula", :integration_test do
    setup_test_formula "testballhome"

    expect { brew "home", "testballhome", "HOMEBREW_BROWSER" => "echo" }
      .to output(/#{testballhome_homepage}/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "opens the homepage for a given Cask", :integration_test, :needs_macos do
    expect { brew "home", local_caffeine_path, "HOMEBREW_BROWSER" => "echo" }
      .to output(/#{local_caffeine_homepage}/).to_stdout
      .and output(/Treating #{Regexp.escape(local_caffeine_path)} as a cask/).to_stderr
      .and be_a_success
    expect { brew "home", "--cask", local_caffeine_path, "HOMEBREW_BROWSER" => "echo" }
      .to output(/#{local_caffeine_homepage}/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "opens the homepages for a given formula and Cask", :integration_test, :needs_macos do
    setup_test_formula "testballhome"

    expect { brew "home", "testballhome", local_caffeine_path, "HOMEBREW_BROWSER" => "echo" }
      .to output(/#{testballhome_homepage} #{local_caffeine_homepage}/).to_stdout
      .and output(/Treating #{Regexp.escape(local_caffeine_path)} as a cask/).to_stderr
      .and be_a_success
  end
end
