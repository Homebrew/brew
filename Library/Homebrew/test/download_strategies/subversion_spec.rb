# frozen_string_literal: true

require "download_strategy"

describe SubversionDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { "1.2.3" }
  let(:specs) { {} }

  describe "#fetch" do
    context "with :trust_cert set" do
      let(:specs) { { trust_cert: true } }

      it "adds the appropriate svn args" do
        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: array_including("--trust-server-cert", "--non-interactive")))
        strategy.fetch
      end
    end

    context "with :revision set" do
      let(:specs) { { revision: "10" } }

      it "adds svn arguments for :revision" do
        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: array_including_cons("-r", "10")))

        strategy.fetch
      end
    end
  end
end
