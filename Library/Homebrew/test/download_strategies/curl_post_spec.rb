# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlPostDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { "1.2.3" }
  let(:specs) { {} }
  let(:head_response) do
    <<~HTTP
      HTTP/1.1 200\r
      Content-Disposition: attachment; filename="foo.tar.gz"
    HTTP
  end

  describe "#fetch" do
    before do
      allow(strategy).to receive(:curl_version).and_return(Version.new("8.6.0"))

      allow(strategy).to receive(:system_command)
        .with(
          /curl/,
          hash_including(args: array_including("--head")),
        )
        .twice
        .and_return(instance_double(
                      SystemCommand::Result,
                      success?:    true,
                      exit_status: instance_double(Process::Status, exitstatus: 0),
                      stdout:      head_response,
                    ))

      strategy.temporary_path.dirname.mkpath
      FileUtils.touch strategy.temporary_path
    end

    context "with :using and :data specified" do
      let(:specs) do
        {
          using: :post,
          data:  {
            form: "data",
            is:   "good",
          },
        }
      end

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("-d", "form=data").and(array_including_cons("-d", "is=good"))),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with :using but no :data" do
      let(:specs) { { using: :post } }

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("-X", "POST")),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "when a secure URL redirects to an insecure URL" do
      let(:url) { "https://example.com/foo.tar.gz?form=data" }
      let(:resolved_url) { "http://example.com/foo.tar.gz" }
      let(:specs) { { using: :post } }

      before do
        allow(Homebrew::EnvConfig).to receive(:no_insecure_redirect?).and_return(true)
        allow(strategy).to receive(:resolve_url_basename_time_file_size)
          .and_return([resolved_url, "foo.tar.gz", nil, nil, nil, true])
      end

      it "raises before downloading" do
        expect(strategy).not_to receive(:curl_download)

        expect { strategy.fetch }
          .to raise_error(CurlDownloadStrategyError, /HTTPS to HTTP redirect detected/)
      end
    end
  end
end
