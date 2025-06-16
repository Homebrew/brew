# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { "1.2.3" }
  let(:specs) { { user: "download:123456" } }
  let(:artifact_domain) { nil }
  let(:headers) do
    {
      "accept-ranges"  => "bytes",
      "content-length" => "37182",
    }
  end

  before do
    allow(strategy).to receive(:curl_headers).with(any_args)
                                             .and_return({ responses: [{ headers: }] })
  end

  it "parses the opts and sets the corresponding args" do
    expect(strategy.send(:_curl_args)).to eq(["--user", "download:123456"])
  end

  describe "#fetch" do
    before do
      allow(Homebrew::EnvConfig).to receive(:artifact_domain).and_return(artifact_domain)

      strategy.temporary_path.dirname.mkpath
      FileUtils.touch strategy.temporary_path
    end

    it "calls curl with default arguments" do
      expect(strategy).to receive(:curl).with(
        "--remote-time",
        "--output", an_instance_of(String),
        # example.com supports partial requests.
        "--continue-at", "-",
        "--location",
        url,
        an_instance_of(Hash)
      )

      strategy.fetch
    end

    context "with an explicit user agent" do
      let(:specs) { { user_agent: "Mozilla/25.0.1" } }

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("--user-agent", "Mozilla/25.0.1")),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with a generalized fake user agent" do
      alias_matcher :a_string_matching, :match

      let(:specs) { { user_agent: :fake } }

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons(
              "--user-agent",
              a_string_matching(/Mozilla.*Mac OS X 10_15_7.*AppleWebKit/),
            )),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with cookies set" do
      let(:specs) do
        {
          cookies: {
            coo: "k/e",
            mon: "ster",
          },
        }
      end

      it "adds the appropriate curl args and does not URL-encode the cookies" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("-b", "coo=k/e;mon=ster")),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with referer set" do
      let(:specs) { { referer: "https://somehost/also" } }

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("-e", "https://somehost/also")),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with headers set" do
      alias_matcher :a_string_matching, :match

      let(:specs) { { headers: ["foo", "bar"] } }

      it "adds the appropriate curl args" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(
              args: array_including_cons("--header", "foo").and(array_including_cons("--header", "bar")),
            ),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end

    context "with artifact_domain set" do
      let(:artifact_domain) { "https://mirror.example.com/oci" }

      context "with an asset hosted under example.com" do
        it "leaves the URL unchanged" do
          expect(strategy).to receive(:system_command)
            .with(
              /curl/,
              hash_including(args: array_including_cons(url)),
            )
            .at_least(:once)
            .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

          strategy.fetch
        end
      end

      context "with an asset hosted under #{GitHubPackages::URL_DOMAIN} (HTTP)" do
        let(:resource_path) { "v2/homebrew/core/spec/manifests/0.0" }
        let(:url) { "http://#{GitHubPackages::URL_DOMAIN}/#{resource_path}" }
        let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

        it "rewrites the URL correctly" do
          expect(strategy).to receive(:system_command)
            .with(
              /curl/,
              hash_including(args: array_including_cons("#{artifact_domain}/#{resource_path}")),
            )
            .at_least(:once)
            .and_return(SystemCommand::Result.new(["curl"], [""], status, secrets: []))

          strategy.fetch
        end
      end

      context "with an asset hosted under #{GitHubPackages::URL_DOMAIN} (HTTPS)" do
        let(:resource_path) { "v2/homebrew/core/spec/manifests/0.0" }
        let(:url) { "https://#{GitHubPackages::URL_DOMAIN}/#{resource_path}" }
        let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

        it "rewrites the URL correctly" do
          expect(strategy).to receive(:system_command)
            .with(
              /curl/,
              hash_including(args: array_including_cons("#{artifact_domain}/#{resource_path}")),
            )
            .at_least(:once)
            .and_return(SystemCommand::Result.new(["curl"], [""], status, secrets: []))

          strategy.fetch
        end
      end
    end
  end

  describe "#cached_location" do
    subject(:cached_location) { strategy.cached_location }

    context "when URL ends with file" do
      it "falls back to the file name in the URL" do
        expect(cached_location).to eq(
          HOMEBREW_CACHE/"downloads/3d1c0ae7da22be9d83fb1eb774df96b7c4da71d3cf07e1cb28555cf9a5e5af70--foo.tar.gz",
        )
      end
    end

    context "when URL file is in middle" do
      let(:url) { "https://example.com/foo.tar.gz/from/this/mirror" }

      it "falls back to the file name in the URL" do
        expect(cached_location).to eq(
          HOMEBREW_CACHE/"downloads/1ab61269ba52c83994510b1e28dd04167a2f2e8393a35a9c50c1f7d33fd8f619--foo.tar.gz",
        )
      end
    end

    context "with a file name trailing the URL path" do
      let(:url) { "https://example.com/cask.dmg" }

      it "falls back to the file extension in the URL" do
        expect(cached_location.extname).to eq(".dmg")
      end
    end

    context "with a file name trailing the first query parameter" do
      let(:url) { "https://example.com/download?file=cask.zip&a=1" }

      it "falls back to the file extension in the URL" do
        expect(cached_location.extname).to eq(".zip")
      end
    end

    context "with a file name trailing the second query parameter" do
      let(:url) { "https://example.com/dl?a=1&file=cask.zip&b=2" }

      it "falls back to the file extension in the URL" do
        expect(cached_location.extname).to eq(".zip")
      end
    end

    context "with an unusually long query string" do
      let(:url) do
        [
          "https://node49152.ssl.fancycdn.example.com",
          "/fancycdn/node/49152/file/upload/download",
          "?cask_class=zf920df",
          "&cask_group=2348779087242312",
          "&cask_archive_file_name=cask.zip",
          "&signature=CGmDulxL8pmutKTlCleNTUY%2FyO9Xyl5u9yVZUE0",
          "uWrjadjuz67Jp7zx3H7NEOhSyOhu8nzicEHRBjr3uSoOJzwkLC8L",
          "BLKnz%2B2X%2Biq5m6IdwSVFcLp2Q1Hr2kR7ETn3rF1DIq5o0lHC",
          "yzMmyNe5giEKJNW8WF0KXriULhzLTWLSA3ZTLCIofAdRiiGje1kN",
          "YY3C0SBqymQB8CG3ONn5kj7CIGbxrDOq5xI2ZSJdIyPysSX7SLvE",
          "DBw2KdR24q9t1wfjS9LUzelf5TWk6ojj8p9%2FHjl%2Fi%2FVCXN",
          "N4o1mW%2FMayy2tTY1qcC%2FTmqI1ulZS8SNuaSgr9Iys9oDF1%2",
          "BPK%2B4Sg==",
        ].join
      end

      it "falls back to the file extension in the URL" do
        expect(cached_location.extname).to eq(".zip")
        expect(cached_location.to_path.length).to be_between(0, 255)
      end
    end
  end
end
