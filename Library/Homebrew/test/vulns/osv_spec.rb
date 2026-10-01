# typed: true
# frozen_string_literal: true

require "vulns/osv"

RSpec.describe Homebrew::Vulns::OSV, :needs_utils_curl do
  def curl_result(stdout:, success: true, http_status: 200, exit_status: success ? 0 : 22)
    instance_double(SystemCommand::Result, stdout: "#{stdout}\n#{http_status}", success?: success, exit_status:,
                    stderr: "")
  end

  def stub_curl(*results)
    allow(Utils::Curl).to receive(:curl_output).and_return(*results)
  end

  describe ".query_batch" do
    let(:packages) do
      [
        { ecosystem: "GIT", name: "https://github.com/a/a", version: "v1" },
        { ecosystem: "GIT", name: "https://github.com/b/b", version: "v2" },
        { ecosystem: "GIT", name: "https://github.com/c/c", version: "v3" },
      ]
    end

    it "returns an array of vuln arrays aligned with the input" do
      body = {
        results: [
          { vulns: [{ id: "CVE-2024-1111" }] },
          { vulns: [] },
          { vulns: [{ id: "CVE-2024-2222" }, { id: "CVE-2024-3333" }] },
        ],
      }
      stub_curl curl_result(stdout: body.to_json)

      results = described_class.query_batch(packages)

      expect(results.size).to eq 3
      expect(results.fetch(0).map { |v| v["id"] }).to eq ["CVE-2024-1111"]
      expect(results.fetch(1)).to eq []
      expect(results.fetch(2).map { |v| v["id"] }).to eq ["CVE-2024-2222", "CVE-2024-3333"]
    end

    it "posts each package under its given ecosystem, omitting version when nil" do
      mixed = [
        { ecosystem: "GIT", name: "https://github.com/a/a", version: "v1" },
        { ecosystem: "PyPI", name: "requests", version: "2.31.0" },
        { ecosystem: "Debian", name: "curl", version: nil },
      ]
      posted = T.let({}, T::Hash[String, T.untyped])
      expect(Utils::Curl).to receive(:curl_output) do |*args, **_options|
        expect(args.last).to eq "https://api.osv.dev/v1/querybatch"
        posted = JSON.parse(args[args.index("--json") + 1])
        curl_result(stdout: { results: [{}, {}, {}] }.to_json)
      end

      described_class.query_batch(mixed)

      expect(posted["queries"]).to eq [
        { "package" => { "name" => "https://github.com/a/a", "ecosystem" => "GIT" }, "version" => "v1" },
        { "package" => { "name" => "requests", "ecosystem" => "PyPI" }, "version" => "2.31.0" },
        { "package" => { "name" => "curl", "ecosystem" => "Debian" } },
      ]
    end

    it "does not classify a missing query endpoint as a missing vulnerability" do
      stub_curl curl_result(stdout: "", success: false, http_status: 404)

      expect { described_class.query_batch(packages) }
        .to raise_error(an_instance_of(Homebrew::Vulns::OSV::ApiError))
    end

    it "returns empty for empty input without hitting the network" do
      expect(Utils::Curl).not_to receive(:curl_output)
      expect(described_class.query_batch([])).to eq []
    end

    it "splits requests larger than BATCH_SIZE and reassembles results in order" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      expect(Utils::Curl).to receive(:curl_output).twice.and_return(
        curl_result(stdout: { results: [{ vulns: [{ id: "A" }] }, { vulns: [{ id: "B" }] }] }.to_json),
        curl_result(stdout: { results: [{ vulns: [{ id: "C" }] }] }.to_json),
      )

      results = described_class.query_batch(packages)

      expect(results.map { |r| r.fetch(0)["id"] }).to eq %w[A B C]
    end

    it "raises ApiError when the results key is missing" do
      stub_curl curl_result(stdout: "{}")
      expect { described_class.query_batch(packages) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /expected 3 results/)
    end

    it "raises ApiError when fewer results than queries are returned" do
      body = { results: [{ vulns: [] }, { vulns: [] }] }
      stub_curl curl_result(stdout: body.to_json)
      expect { described_class.query_batch(packages) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /expected 3 results, got 2/)
    end

    it "raises ApiError when a continuation response is truncated" do
      page1 = {
        results: [
          { vulns: [{ id: "A1" }], next_page_token: "tok-a" },
          { vulns: [{ id: "B1" }], next_page_token: "tok-b" },
          { vulns: [{ id: "C1" }] },
        ],
      }
      page2 = { results: [{ vulns: [{ id: "A2" }] }] }
      stub_curl(curl_result(stdout: page1.to_json), curl_result(stdout: page2.to_json))
      expect { described_class.query_batch(packages) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /expected 2 results, got 1/)
    end

    it "follows per-result next_page_token, resubmitting only paged queries" do
      page1 = {
        results: [
          { vulns: [{ id: "A1" }] },
          { vulns: [{ id: "B1" }], next_page_token: "tok-b" },
          { vulns: [{ id: "C1" }] },
        ],
      }
      page2 = { results: [{ vulns: [{ id: "B2" }, { id: "B3" }] }] }
      posted = T.let([], T::Array[T::Hash[String, T.untyped]])
      expect(Utils::Curl).to receive(:curl_output).twice do |*args, **_options|
        posted << JSON.parse(args[args.index("--json") + 1])
        curl_result(stdout: ((posted.size == 1) ? page1 : page2).to_json)
      end

      results = described_class.query_batch(packages)

      expect(results.fetch(0).map { |v| v["id"] }).to eq %w[A1]
      expect(results.fetch(1).map { |v| v["id"] }).to eq %w[B1 B2 B3]
      expect(results.fetch(2).map { |v| v["id"] }).to eq %w[C1]
      expect(posted.fetch(1)["queries"]).to eq [
        { "package"    => { "name" => "https://github.com/b/b", "ecosystem" => "GIT" },
          "version"    => "v2",
          "page_token" => "tok-b" },
      ]
    end

    it "raises after MAX_PAGES continuation requests" do
      stub_const("#{described_class}::MAX_PAGES", 3)
      body = { results: [{ vulns: [{ id: "LOOP" }], next_page_token: "again" }] }
      stub_curl curl_result(stdout: body.to_json)

      expect { described_class.query_batch([packages.first]) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /more than 3 pages/)
    end

    it "raises ApiError when curl reports failure" do
      stub_curl curl_result(stdout: "server on fire", success: false)
      expect { described_class.query_batch(packages) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /OSV API/)
    end

    it "raises ApiError when the response is not valid JSON" do
      stub_curl curl_result(stdout: "<html>not json</html>")
      expect { described_class.query_batch(packages) }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /Invalid JSON/)
    end
  end

  it "bounds requests while retaining the curl wrapper's retry policy" do
    options = T.let({}, T::Hash[Symbol, Integer])
    allow(Utils::Curl).to receive(:curl_output) do |*_args, **kwargs|
      options = kwargs
      curl_result(stdout: '{"id":"CVE-2024-1234"}')
    end

    described_class.vulnerability("CVE-2024-1234")

    expect(options).to eq(connect_timeout: 15, max_time: 60, retry_max_time: 120)
  end

  describe ".vulnerability" do
    it "fetches a single vulnerability record by id" do
      body = {
        id:       "CVE-2024-1234",
        summary:  "Test vulnerability",
        details:  "Full details here",
        severity: [{ type: "CVSS_V3", score: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H" }],
      }
      stub_curl curl_result(stdout: body.to_json)

      vuln = described_class.vulnerability("CVE-2024-1234")

      expect(vuln["id"]).to eq "CVE-2024-1234"
      expect(vuln["summary"]).to eq "Test vulnerability"
      expect(vuln["details"]).to eq "Full details here"
    end

    it "distinguishes a confirmed HTTP 404 from other request failures" do
      stub_curl curl_result(stdout: "", success: false, http_status: 404)

      expect { described_class.vulnerability("CVE-2024-0404") }
        .to raise_error(Homebrew::Vulns::OSV::NotFoundError)
    end

    it "does not treat a timeout after HTTP 404 headers as a confirmed missing record" do
      stub_curl curl_result(stdout: "", success: false, http_status: 404, exit_status: 28)

      expect { described_class.vulnerability("CVE-2024-0404") }
        .to raise_error(an_instance_of(Homebrew::Vulns::OSV::ApiError))
    end

    it "keeps server errors distinct from a missing record" do
      stub_curl curl_result(stdout: "", success: false, http_status: 503)

      expect { described_class.vulnerability("CVE-2024-0404") }
        .to raise_error(an_instance_of(Homebrew::Vulns::OSV::ApiError))
    end

    it "URL-encodes the id in the request path" do
      requested = T.let("", String)
      expect(Utils::Curl).to receive(:curl_output) do |*args, **_options|
        requested = args.fetch(-1)
        curl_result(stdout: { id: "GO-2024-1/2" }.to_json)
      end

      described_class.vulnerability("GO-2024-1/2")

      expect(requested).to eq "https://api.osv.dev/v1/vulns/GO-2024-1%2F2"
    end

    it "raises ApiError when curl reports failure" do
      stub_curl curl_result(stdout: "not found", success: false)
      expect { described_class.vulnerability("CVE-0000-0000") }
        .to raise_error(Homebrew::Vulns::OSV::ApiError, /OSV API/)
    end
  end
end
