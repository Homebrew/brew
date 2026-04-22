# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-portable-ruby"

RSpec.describe Homebrew::DevCmd::UpdatePortableRuby do
  it_behaves_like "parseable arguments"

  describe ".lockfile_in_sync?" do
    let(:lockfile) do
      <<~LOCK
        RUBY VERSION
          ruby 4.0.3

        BUNDLED WITH
          4.0.6
      LOCK
    end

    it "returns true when both versions match" do
      expect(described_class.lockfile_in_sync?(lockfile, "4.0.3", "4.0.6")).to be true
    end

    it "returns false when the Ruby version differs" do
      expect(described_class.lockfile_in_sync?(lockfile, "4.0.2", "4.0.6")).to be false
    end

    it "returns false when the bundler version differs" do
      expect(described_class.lockfile_in_sync?(lockfile, "4.0.3", "4.0.10")).to be false
    end
  end
end
