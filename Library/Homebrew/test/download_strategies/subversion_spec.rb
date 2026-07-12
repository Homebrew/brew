# typed: true
# frozen_string_literal: true

require "download_strategy"
require "utils/svn"

RSpec.describe SubversionDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { "1.2.3" }
  let(:specs) { {} }

  describe "#fetch" do
    before do
      allow(strategy).to receive(:repo_url).and_return("#{url}/old")
    end

    context "with :trust_cert set" do
      let(:specs) { { trust_cert: true } }

      before do
        allow(Utils::Svn).to receive(:version).and_return("1.14.5")
      end

      it "adds the appropriate svn args" do
        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: array_including("--trust-server-cert", "--non-interactive")))
          .and_return(instance_double(SystemCommand::Result))

        strategy.fetch
      end
    end

    context "with :revision set" do
      let(:specs) { { revision: "10" } }

      it "adds svn arguments for :revision" do
        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: array_including_cons("-r", "10")))
          .and_return(instance_double(SystemCommand::Result))

        strategy.fetch
      end
    end

    context "with :revisions set" do
      let(:specs) { { revisions: { trunk: "10", "external" => "11" } } }

      it "keeps checkout operands after options" do
        external_url = "-example"

        allow(strategy).to receive(:silent_command)
          .with("svn", args: ["propget", "svn:externals", url])
          .and_return(instance_double(SystemCommand::Result, stdout: "external #{external_url}\n"))

        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: ["checkout", "--quiet", "-r", "10", "--ignore-externals", "--", url,
                                             strategy.cached_location]))
          .and_return(instance_double(SystemCommand::Result))
        expect(strategy).to receive(:system_command!)
          .with("svn", hash_including(args: ["checkout", "--quiet", "-r", "11", "--ignore-externals", "--",
                                             external_url, strategy.cached_location/"external"]))
          .and_return(instance_double(SystemCommand::Result))

        strategy.fetch
      end
    end
  end
end
