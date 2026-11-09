# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe AbstractDownloadStrategy do
  subject(:strategy) { Class.new(described_class).new(url, name, version, **specs) }

  let(:specs) { {} }
  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { nil }

  specify "#source_modified_time" do
    mktmpdir("mtime").cd do
      FileUtils.touch "foo", mtime: Time.now - 10
      FileUtils.touch "bar", mtime: Time.now - 100
      FileUtils.ln_s "not-exist", "baz"
      expect(strategy.source_modified_time).to eq(File.mtime("foo"))
    end
  end

  describe "#command!" do
    subject(:strategy) do
      Class.new(described_class) do
        T.bind(self, T.class_of(AbstractDownloadStrategy))
        public :command!
      end.new(url, name, version)
    end

    it "merges the caller's environment into the strategy's" do
      allow(strategy).to receive(:env).and_return({ "STRATEGY" => "1" })
      expect(strategy).to receive(:system_command!)
        .with("true", hash_including(env: { "STRATEGY" => "1", "CALLER" => "1" }))
        .and_return(instance_double(SystemCommand::Result))

      strategy.command!("true", args: [], env: { "CALLER" => "1" })
    end
  end
end
