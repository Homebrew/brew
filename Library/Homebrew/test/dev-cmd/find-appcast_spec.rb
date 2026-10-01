# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/find-appcast"

RSpec.describe Homebrew::DevCmd::FindAppcast do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "find-appcast"

  it "reports when the app has no appcast" do
    expect { described_class.new([mktmpdir.to_s]).run }.to output("No appcast found.\n").to_stdout
  end

  it "escapes the URL in the suggested livecheck block" do
    result = Cask::Appcast::Result.new(url: 'https://example.com/"appcast".xml', strategy: :sparkle)
    allow(Cask::Appcast).to receive(:find).and_return(result)
    expect { described_class.new([mktmpdir.to_s]).run }
      .to output(%r{^  url "https://example\.com/\\"appcast\\"\.xml"$}).to_stdout
  end
end
