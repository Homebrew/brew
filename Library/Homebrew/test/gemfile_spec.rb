# typed: strict
# frozen_string_literal: true

require "bundler"

RSpec.describe Bundler::Definition do
  it "accepts any Ruby from the Gemfiles' minimum version upwards" do
    candidates = %w[3.4.9 4.0.0 4.0.7 4.1.0 5.0.0]
    gemfiles = { "Library/Homebrew/Gemfile" => "../Gemfile", "docs/Gemfile" => "../../../docs/Gemfile" }
    accepted_rubies = gemfiles.transform_values do |gemfile|
      ruby_version = described_class.build(File.expand_path(gemfile, __dir__), nil, false).ruby_version
      raise "#{gemfile} must declare its Ruby requirement" unless ruby_version

      candidates.select { |candidate| ruby_version.diff(Bundler::RubyVersion.new(candidate, nil, nil, nil)).nil? }
    end
    expect(accepted_rubies).to eq(
      "Library/Homebrew/Gemfile" => %w[4.0.0 4.0.7 4.1.0 5.0.0],
      "docs/Gemfile"             => %w[4.0.0 4.0.7 4.1.0 5.0.0],
    )
  end
end
