# typed: true
# frozen_string_literal: true

require "cmd/home"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Home do
  let(:testballhome) do
    formula("testballhome") do
      T.bind(self, T.class_of(Formula))
      homepage "https://brew.sh/testballhome"
      url "https://brew.sh/testballhome-1.0"
    end
  end
  let(:testballhome_homepage) do
    testballhome.homepage
  end

  let(:local_caffeine_path) do
    cask_path("local-caffeine")
  end

  let(:local_caffeine_homepage) do
    Cask::CaskLoader.load(local_caffeine_path).homepage
  end

  it_behaves_like "parseable arguments"

  it "opens the homepages for a given Formula and Cask", :cask, :integration_test do
    setup_test_formula "testballhome", <<~RUBY
      homepage "#{testballhome_homepage}"
    RUBY

    expect { brew "home", "testballhome", local_caffeine_path, "HOMEBREW_BROWSER" => "echo" }
      .to output(/#{Regexp.escape(testballhome_homepage)}.*#{Regexp.escape(local_caffeine_homepage)}/m).to_stdout
      .and output(/Treating #{Regexp.escape(local_caffeine_path)} as a cask/).to_stderr
      .and be_a_success
    expect { brew "home", "HOMEBREW_BROWSER" => "echo" }
      .to output("https://brew.sh\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "opens the homepage for a given Formula" do
    stub_formula_loader testballhome, call_original: true
    cmd = described_class.new(["testballhome"])
    expect(Utils::Browser).to receive(:open).with(testballhome_homepage)

    expect { cmd.run }
      .to output(/Opening homepage for Formula testballhome/).to_stdout
      .and not_to_output.to_stderr
  end

  it "opens the homepage for a given Cask", :cask, :needs_macos do
    cmd = described_class.new([local_caffeine_path.to_s])
    expect(Utils::Browser).to receive(:open).with(local_caffeine_homepage)

    expect { cmd.run }
      .to output(/Opening homepage for Cask local-caffeine/).to_stdout
      .and output(/Treating #{Regexp.escape(local_caffeine_path)} as a cask/).to_stderr
    cmd = described_class.new(["--cask", local_caffeine_path.to_s])
    expect(Utils::Browser).to receive(:open).with(local_caffeine_homepage)

    expect { cmd.run }
      .to output(/Opening homepage for Cask local-caffeine/).to_stdout
      .and not_to_output.to_stderr
  end

  it "opens the homepages for a given formula and Cask", :cask, :needs_macos do
    stub_formula_loader testballhome, call_original: true
    cmd = described_class.new(["testballhome", local_caffeine_path.to_s])
    expect(Utils::Browser).to receive(:open).with(testballhome_homepage, local_caffeine_homepage)

    expect { cmd.run }
      .to output(/Opening homepage for Formula testballhome.*Opening homepage for Cask local-caffeine/m).to_stdout
      .and output(/Treating #{Regexp.escape(local_caffeine_path)} as a cask/).to_stderr
  end
end
