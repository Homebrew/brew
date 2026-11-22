# typed: true
# frozen_string_literal: true

require "utils/shared_audits"
require "utils/curl"

RSpec.describe SharedAudits do
  let(:eol_json_text) do
    <<~JSON
      {
        "schema_version" : "1.0.0",
        "generated_at": "2025-01-02T01:23:45+00:00",
        "result": {
          "name": "1.2",
          "codename": null,
          "label": "1.2",
          "releaseDate": "2024-01-01",
          "isLts": false,
          "ltsFrom": null,
          "isEol": true,
          "eolFrom": "2025-01-01",
          "isMaintained": false,
          "latest": {
            "name": "1.0.0",
            "date": "2024-01-01",
            "link": "https://example.com/1.0.0"
          }
        }
      }
    JSON
  end

  def command_result(stdout, success: true)
    status = instance_double(Process::Status, success?: success)
    instance_double(SystemCommand::Result, stdout:, status:)
  end

  def mock_curl_output(stdout: "", success: true)
    allow(Utils::Curl).to receive(:curl_output).and_return command_result(stdout, success:)
  end

  describe "::homepage_browsed_recently?" do
    before { allow(Date).to receive(:today).and_return(Date.new(2026, 7, 26)) }

    it "returns true for a date less than a year ago" do
      expect(described_class.homepage_browsed_recently?(Date.new(2025, 7, 27))).to be(true)
    end

    it "returns false for a date a year ago" do
      expect(described_class.homepage_browsed_recently?(Date.new(2025, 7, 26))).to be(false)
    end

    it "returns false for a future date" do
      expect(described_class.homepage_browsed_recently?(Date.new(2026, 7, 27))).to be(false)
    end

    it "returns false without a date" do
      expect(described_class.homepage_browsed_recently?(nil)).to be(false)
    end
  end

  describe "::eol_data" do
    it "returns a parsed JSON object if the product is found" do
      mock_curl_output stdout: eol_json_text
      expect(described_class.eol_data("product", "cycle")&.dig("result", "isEol")).to be(true)
      expect(described_class.eol_data("product", "cycle")&.dig("result", "eolFrom")).to eq("2025-01-01")
    end

    it "returns nil if the product is not found" do
      mock_curl_output stdout: "<html></html>"
      expect(described_class.eol_data("none", "cycle")).to be_nil
    end

    it "returns nil if api call fails" do
      mock_curl_output success: false
      expect(described_class.eol_data("", "")).to be_nil
    end
  end

  describe "::new_domain_problem" do
    let(:rdap_bootstrap) { { "services" => [[["dev"], ["https://rdap.example/"]]] } }
    let(:rdap_registration) do
      { "events" => [{ "eventAction" => "registration", "eventDate" => "2026-07-01T15:50:45Z" }] }
    end
    let(:whois_output) do
      <<~WHOIS
        % IANA WHOIS server
        domain:       SH
        created:      1997-09-23

        # whois.nic.sh
        Domain Name: brew.sh
        Creation Date: 2026-07-01T15:50:45Z
      WHOIS
    end

    before do
      allow(Date).to receive(:today).and_return(Date.new(2026, 7, 26))
      allow(described_class).to receive(:which).with("whois").and_return(Pathname("/usr/bin/whois"))
      described_class.rdap_services = nil
      mock_rdap
    end

    def mock_rdap(responses = {})
      allow(Utils::Curl).to receive(:curl_output) do |*args, **_options|
        url = args.fetch(-1)
        if url == SharedAudits::RDAP_BOOTSTRAP_URL
          command_result(rdap_bootstrap.to_json)
        else
          status, body = responses.fetch(url.delete_prefix("https://rdap.example/domain/"), [404, {}])
          command_result("HTTP/2 #{status}\r\ncontent-type: application/rdap+json\r\n\r\n#{body.to_json}")
        end
      end
    end

    def mock_whois(stdout:, success: true)
      allow(SystemCommand).to receive(:run).and_return(command_result(stdout, success:))
    end

    it "reports domains registered less than 30 days ago according to RDAP" do
      mock_rdap "brew.dev" => [200, rdap_registration]

      expect(described_class.new_domain_problem("https://www.brew.dev/foo"))
        .to include("`homepage` domain `brew.dev` was registered on 2026-07-01")
    end

    it "ignores domains registered at least 30 days ago according to RDAP" do
      rdap_registration["events"].first["eventDate"] = "2026-06-26T15:50:45Z"
      mock_rdap "brew.dev" => [200, rdap_registration]

      expect(described_class.new_domain_problem("https://brew.dev")).to be_nil
    end

    it "walks up from a subdomain to the registered domain" do
      mock_rdap "docs.brew.dev" => [400, {}], "brew.dev" => [200, rdap_registration]

      expect(described_class.new_domain_problem("https://docs.brew.dev"))
        .to include("`homepage` domain `brew.dev` was registered on 2026-07-01")
    end

    it "falls back to `whois` when the registry publishes no registration date over RDAP" do
      mock_rdap "brew.dev" => [200, { "events" => [{ "eventAction" => "last changed" }] }]
      mock_whois stdout: whois_output

      expect(described_class.new_domain_problem("https://brew.dev"))
        .to include("`homepage` domain `brew.dev` was registered on 2026-07-01")
    end

    it "falls back to `whois` when the RDAP server fails" do
      mock_rdap "brew.dev" => [503, {}]
      mock_whois stdout: whois_output

      expect(described_class.new_domain_problem("https://brew.dev"))
        .to include("`homepage` domain `brew.dev` was registered on 2026-07-01")
    end

    it "ignores domains neither the RDAP server nor `whois` knows" do
      mock_whois stdout: "No match for domain \"BREW.DEV\".\n"

      expect(described_class.new_domain_problem("https://brew.dev")).to be_nil
    end

    it "falls back to `whois` when the RDAP bootstrap cannot be fetched" do
      mock_curl_output success: false
      mock_whois stdout: whois_output

      expect(described_class.new_domain_problem("https://brew.dev"))
        .to include("`homepage` domain `brew.dev` was registered on 2026-07-01")
    end

    it "reports domains registered less than 30 days ago according to `whois`" do
      mock_whois stdout: whois_output

      expect(described_class.new_domain_problem("https://www.brew.sh/foo"))
        .to include("`homepage` domain `brew.sh` was registered on 2026-07-01")
    end

    it "ignores domains registered at least 30 days ago according to `whois`" do
      mock_whois stdout: whois_output.sub("2026-07-01T15:50:45Z", "2026-06-26T15:50:45Z")

      expect(described_class.new_domain_problem("https://brew.sh")).to be_nil
    end

    it "reports domains registered less than 30 days ago according to Linux `whois`" do
      mock_whois stdout: whois_output.sub("# whois.nic.sh", "Found a referral to whois.nic.sh.")

      expect(described_class.new_domain_problem("https://brew.sh"))
        .to include("`homepage` domain `brew.sh` was registered on 2026-07-01")
    end

    it "parses `whois` registration dates that start with a weekday" do
      mock_whois stdout: whois_output.sub("Creation Date: 2026-07-01T15:50:45Z", "Registered:\tWed Jul 1 2026")

      expect(described_class.new_domain_problem("https://brew.sh"))
        .to include("`homepage` domain `brew.sh` was registered on 2026-07-01")
    end

    it "ignores the IANA record for the TLD when the registry publishes no date" do
      whois_header = whois_output.lines.take(5).join
      mock_whois stdout: "#{whois_header}Domain: brew.sh\nStatus: connect\n"

      expect(described_class.new_domain_problem("https://brew.sh")).to be_nil
    end

    it "tolerates invalid UTF-8 in `whois` output" do
      mock_whois stdout: "#{whois_output}Registrant: \xFF\n"

      expect(described_class.new_domain_problem("https://brew.sh"))
        .to include("`homepage` domain `brew.sh` was registered on 2026-07-01")
    end

    it "ignores domains with no parseable creation date" do
      mock_whois stdout: "No match for domain \"NOPE.INVALID\".\n"

      expect(described_class.new_domain_problem("https://nope.invalid")).to be_nil
    end

    it "ignores domains when `whois` fails" do
      mock_whois stdout: "", success: false

      expect(described_class.new_domain_problem("https://fails.example")).to be_nil
    end

    it "ignores domains when `whois` times out" do
      allow(SystemCommand).to receive(:run).and_raise(Timeout::Error)

      expect(described_class.new_domain_problem("https://slow.example")).to be_nil
    end

    it "ignores domains when `whois` is unavailable" do
      allow(described_class).to receive(:which).with("whois").and_return(nil)

      expect(described_class.new_domain_problem("https://missing.example")).to be_nil
    end

    it "ignores unparseable homepages" do
      expect(described_class.new_domain_problem("not a url")).to be_nil
    end

    test_each(%w[
      https://github.com/foo/bar
      https://gitlab.com/foo/bar
      https://bitbucket.org/foo/bar
      https://codeberg.org/foo/bar
      https://foo.github.io/bar
      https://sr.ht/~foo/bar
    ]) do |homepage|
      it "does not look up the git forge homepage #{homepage}" do
        expect(Utils::Curl).not_to receive(:curl_output)
        expect(SystemCommand).not_to receive(:run)
        expect(described_class.new_domain_problem(homepage)).to be_nil
      end
    end
  end

  describe "::pull_request_commit_email_domains" do
    let(:commits_url) { "https://api.github.com/repos/Homebrew/homebrew-cask/pulls/1/commits" }

    before { described_class.pull_request_commit_email_domains = nil }
    after { described_class.pull_request_commit_email_domains = nil }

    it "returns the email domains of the pull request's commit authors" do
      event_path = mktmpdir/"event.json"
      event_path.write(JSON.generate({ pull_request: { commits_url: } }))
      ENV["GITHUB_EVENT_PATH"] = event_path.to_s
      first_page = [{ "commit" => { "author" => { "email" => "Jo@Acme.io" } } }]
      second_page = [{ "commit" => { "author" => { "email" => "x@brew.sh" } } }]
      allow(GitHub::API).to receive(:paginate_rest).with(commits_url)
                                                   .and_yield(first_page, 1)
                                                   .and_yield(second_page, 2)

      expect(described_class.pull_request_commit_email_domains).to eq(["acme.io", "brew.sh"])
    end

    it "returns no domains outside a pull request" do
      ENV.delete("GITHUB_EVENT_PATH")

      expect(described_class.pull_request_commit_email_domains).to be_empty
    end
  end

  describe "::commit_email_domain_match" do
    before { allow(described_class).to receive(:pull_request_commit_email_domains).and_return(["acme.io"]) }

    it "returns the stanza and domain at a commit author's email domain" do
      expect(described_class.commit_email_domain_match({ homepage: "https://www.acme.io/app" }))
        .to eq([:homepage, "acme.io"])
    end

    it "matches a subdomain of a commit author's email domain" do
      urls = { homepage: "https://acmeapp.com", url: "https://dl.acme.io/app.dmg" }

      expect(described_class.commit_email_domain_match(urls)).to eq([:url, "dl.acme.io"])
    end

    it "ignores other domains" do
      expect(described_class.commit_email_domain_match({ homepage: "https://notacme.io" })).to be_nil
    end

    it "ignores git forge domains" do
      allow(described_class).to receive(:pull_request_commit_email_domains).and_return(["github.com"])

      expect(described_class.commit_email_domain_match({ homepage: "https://github.com/acme/app" })).to be_nil
    end
  end

  describe "::self_submission_problem" do
    before { allow(described_class).to receive(:pull_request_commit_email_domains).and_return(["acme.io"]) }

    it "reports self-submissions without a repository to assess" do
      urls = { homepage: "https://acmeapp.com", url: "https://dl.acme.io/app.dmg" }

      expect(described_class.self_submission_problem(urls)).to include("matches the `url` domain `dl.acme.io`")
    end

    it "reports self-submissions whose git forge pages have no repository to assess" do
      urls = { homepage: "https://acme.github.io", url: "https://acme.io/app.dmg" }

      expect(described_class.self_submission_problem(urls)).to include("matches the `url` domain `acme.io`")
    end

    it "ignores git forge URLs embedded in other URLs" do
      urls = { homepage: "https://acme.io", url: "https://dl.acme.io/app.dmg?source=https://github.com/acme/app" }

      expect(described_class.self_submission_problem(urls)).to include("matches the `homepage` domain `acme.io`")
    end

    it "leaves self-submissions with a repository to the notability audits" do
      urls = { homepage: "https://acme.io", url: "https://github.com/acme/app/releases/download/v1.0/app.dmg" }

      expect(described_class.self_submission_problem(urls)).to be_nil
    end
  end

  describe "::livecheck_required_problem" do
    it "reports a `livecheck` block that uses `skip`" do
      cask = Cask::Cask.new("livecheck-skip") do
        url "https://github.com/acme/app/releases/download/1.0/app.dmg"
        livecheck do
          skip "No version information available"
        end
      end

      expect(described_class.livecheck_required_problem(cask)).to include("uses `skip` in its `livecheck` block")
    end

    it "reports URLs without a default `livecheck` strategy" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        homepage "https://brew.sh"
        url "https://brew.sh/foo-1.0.tar.gz"
      end

      expect(described_class.livecheck_required_problem(f)).to include("New formulae must have a working `livecheck`")
    end

    it "accepts URLs with a default `livecheck` strategy" do
      cask = Cask::Cask.new("livecheck-default") do
        url "https://github.com/acme/app/releases/download/1.0/app.dmg"
        homepage "https://acme.io"
      end

      expect(described_class.livecheck_required_problem(cask)).to be_nil
    end

    it "accepts a `livecheck` block that does not use `skip`" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        homepage "https://brew.sh"
        url "https://brew.sh/foo-1.0.tar.gz"

        livecheck do
          url :homepage
          regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
        end
      end

      expect(described_class.livecheck_required_problem(f)).to be_nil
    end
  end

  describe "::github_tag_from_url" do
    it "finds tags in archive urls" do
      url = "https://github.com/a/b/archive/refs/tags/v1.2.3.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("v1.2.3")
    end

    it "finds tags in release urls" do
      url = "https://github.com/a/b/releases/download/1.2.3/b-1.2.3.tar.bz2"
      expect(described_class.github_tag_from_url(url)).to eq("1.2.3")
    end

    it "finds tags with slashes" do
      url = "https://github.com/a/b/archive/refs/tags/c/d/e/f/g-v1.2.3.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("c/d/e/f/g-v1.2.3")
    end

    it "finds tags in orgs/repos with special characters" do
      url = "https://github.com/a-b/c-d_e.f/archive/refs/tags/2.5.tar.gz"
      expect(described_class.github_tag_from_url(url)).to eq("2.5")
    end
  end

  describe "::gitlab_tag_from_url" do
    it "doesn't find tags in invalid urls" do
      url = "https://gitlab.com/a/-/archive/v1.2.3/a-v1.2.3.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to be_nil
    end

    it "finds tags in basic urls" do
      url = "https://gitlab.com/a/b/-/archive/v1.2.3/b-1.2.3.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("v1.2.3")
    end

    it "finds tags in urls with subgroups" do
      url = "https://gitlab.com/a/b/c/d/e/f/g/-/archive/2.5/g-2.5.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("2.5")
    end

    it "finds tags in urls with special characters" do
      url = "https://gitlab.com/a.b/c-d_e/-/archive/2.5/c-d_e-2.5.tar.gz"
      expect(described_class.gitlab_tag_from_url(url)).to eq("2.5")
    end
  end

  describe "::forgejo_tag_from_url" do
    it "finds tags in basic urls" do
      url = "https://codeberg.org/Aviac/codeberg-cli/archive/v0.4.11.tar.gz"
      expect(described_class.forgejo_tag_from_url(url)).to eq("v0.4.11")
    end

    it "finds tags in urls with subgroups" do
      url = "https://codeberg.org/Aviac/codeberg-cli/archive/some/test/1.2.3.tar.gz"
      expect(described_class.forgejo_tag_from_url(url)).to eq("some/test/1.2.3")
    end

    it "finds tags in orgs/repos with special characters" do
      url = "https://codeberg.org/Aviaca-b_cv/codeberg-cli/archive/v0.4.11.tar.gz"
      expect(described_class.forgejo_tag_from_url(url)).to eq("v0.4.11")
    end
  end
end
