# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlApacheMirrorDownloadStrategy do
  subject(:strategy) { described_class.new(url, "foo", "1.2.3") }

  let(:url) { "https://www.apache.org/dyn/closer.lua?path=foo.tar.gz" }
  let(:start_time) { Time.at(1_700_000_000) }
  let(:mirror_info) do
    {
      preferred: "https://example.com/",
      path_info: "foo.tar.gz",
      backup:    ["https://backup.example.com/"],
    }
  end
  let(:metadata_result) { instance_double(SystemCommand::Result, stdout: mirror_info.to_json) }
  let(:responses) { [{ headers: { "content-length" => "10" } }] }

  before do
    allow(Time).to receive(:now).and_return(start_time)
    allow(strategy).to receive_messages(curl_output: metadata_result, curl_headers: { responses: })
  end

  describe "#fetch" do
    before do
      allow(strategy).to receive(:curl_output).and_raise(Timeout::Error)
    end

    it "bounds the Apache request used to resolve the cache filename" do
      expect(strategy).to receive(:curl_output)
        .with("--silent", "--location", "#{url}&asjson=1", timeout: 3)
        .and_raise(Timeout::Error)

      expect { strategy.fetch(timeout: 3) }.to raise_error(Timeout::Error)
    end

    context "with a cached download" do
      before do
        cached_path = HOMEBREW_CACHE/"downloads/#{Digest::SHA256.hexdigest(url)}--foo.tar.gz"
        cached_path.dirname.mkpath
        cached_path.write("cached")
      end

      it "bounds the Apache request used to find backup mirrors" do
        expect(strategy).to receive(:curl_output)
          .with("--silent", "--location", "#{url}&asjson=1", timeout: 3)
          .and_raise(Timeout::Error)

        expect { strategy.fetch(timeout: 3) }.to raise_error(Timeout::Error)
      end
    end

    it "clears the Apache request deadline after a failed fetch" do
      begin
        strategy.fetch(timeout: 3)
      rescue Timeout::Error
        nil
      end

      expect(strategy).to receive(:curl_output)
        .with("--silent", "--location", "#{url}&asjson=1", timeout: nil)
        .and_return(metadata_result)

      strategy.mirrors
    end
  end

  describe "#resolved_time_file_size" do
    let(:lookup_duration) { 2 }

    before do
      allow(strategy).to receive(:curl_output) do
        allow(Time).to receive(:now).and_return(start_time + lookup_duration)
        metadata_result
      end
    end

    it "includes Apache mirror resolution in the lookup deadline" do
      expect(strategy).to receive(:curl_headers)
        .with("https://example.com/foo.tar.gz", wanted_headers: ["content-disposition"], deadline: start_time + 3)
        .and_return({ responses: })

      strategy.resolved_time_file_size(timeout: 3)
    end

    context "when Apache mirror resolution exhausts the timeout" do
      let(:lookup_duration) { 3 }

      it "does not start the mirror header request" do
        expect(strategy).not_to receive(:curl_headers)
        expect { strategy.resolved_time_file_size(timeout: 3) }.to raise_error(Timeout::Error)
      end
    end
  end
end
