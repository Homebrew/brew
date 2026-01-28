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

  def mock_curl_output(stdout: "", success: true)
    status = instance_double(Process::Status, success?: success)
    curl_output = instance_double(SystemCommand::Result, stdout:, status:)
    allow(Utils::Curl).to receive(:curl_output).and_return curl_output
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
