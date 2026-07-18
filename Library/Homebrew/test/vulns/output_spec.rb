# typed: true
# frozen_string_literal: true

require "vulns/output"
require "vulns/scanner"
require "vulns/vulnerability"

RSpec.describe Homebrew::Vulns::Output do
  def vuln(id, severity: "HIGH", summary: nil, aliases: [], fixed: [])
    data = { "id" => id, "aliases" => aliases }
    data["summary"] = summary if summary
    data["database_specific"] = { "severity" => severity } if severity
    data["affected"] = [{ "ranges" => [{ "events" => fixed.map { |v| { "fixed" => v } } }] }] if fixed.any?
    Homebrew::Vulns::Vulnerability.new(data)
  end

  def finding(name:, version:, tag: "v#{version}", repo_url: "https://github.com/x/#{name}", open: [], patched: [])
    Homebrew::Vulns::Scanner::Finding.new(name:, version:, tag:, repo_url:, open:, patched:)
  end

  def results(findings, checked: findings.size, skipped: 0)
    Homebrew::Vulns::Scanner::Results.new(findings:, checked:, skipped:)
  end

  describe ".text" do
    def render(res, **opts)
      out = +""
      described_class.text(res, io: StringIO.new(out), **opts)
      Tty.strip_ansi(out)
    end

    it "prints a clean message when there are no findings" do
      expect(render(results([]))).to include "No vulnerabilities found."
    end

    it "distinguishes the clean message when only patched findings exist" do
      f = finding(name: "libquicktime", version: "1.2.4", patched: [vuln("CVE-2016-2399")])
      out = render(results([f]))
      expect(out).to include "No open vulnerabilities found."
      expect(out).not_to include "No vulnerabilities found.\n"
    end

    it "prints formula, version, vuln id, severity and summary" do
      f = finding(name: "vim", version: "9.1.2050",
                  open: [vuln("CVE-2024-1234", severity: "HIGH", summary: "Heap overflow")])
      out = render(results([f]))
      expect(out).to include "vim (9.1.2050)"
      expect(out).to include "CVE-2024-1234 (HIGH) - Heap overflow"
    end

    it "prints fixed versions when present" do
      f = finding(name: "vim", version: "9.1.2050",
                  open: [vuln("CVE-2024-1234", fixed: ["v9.1.3000", "v10.0.0"])])
      expect(render(results([f]))).to include "Fixed in: v9.1.3000, v10.0.0"
    end

    it "prints a totals line" do
      f = finding(name: "vim", version: "9.1.2050",
                  open: [vuln("CVE-2024-1111"), vuln("CVE-2024-2222")])
      expect(render(results([f]))).to include "Found 2 vulnerabilities in 1 package"
    end

    it "truncates summaries at max_summary" do
      f = finding(name: "vim", version: "9.1", open: [vuln("CVE-1", summary: "A" * 100)])
      out = render(results([f]), max_summary: 60)
      expect(out).to include "#{"A" * 60}..."
      expect(out).not_to include "A" * 100
    end

    it "disables truncation when max_summary is 0" do
      f = finding(name: "vim", version: "9.1", open: [vuln("CVE-1", summary: "A" * 100)])
      out = render(results([f]), max_summary: 0)
      expect(out).to include "A" * 100
      expect(out).not_to include "A..."
    end

    it "omits the summary segment when the summary is nil" do
      f = finding(name: "vim", version: "9.1", open: [vuln("CVE-2024-1234", severity: nil)])
      out = render(results([f]))
      expect(out).to include "CVE-2024-1234 (UNKNOWN)"
      expect(out).not_to match(/CVE-2024-1234 \(UNKNOWN\) - $/)
    end

    it "strips terminal escape sequences from OSV-sourced fields" do
      summary = "safe \e[2J\e[31mred\e[0m \e]0;pwned\a c1 \u{009b}2Jblue\u{009d}0;owned\a \rhidden\b text"
      f = finding(name: "vim", version: "9.1",
                  open: [vuln("CVE-2024-1234\e[2J", summary:, fixed: ["1.2.3\e[31m"])])
      out = +""
      described_class.text(results([f]), io: StringIO.new(out), max_summary: 0)
      expect(out).to include "safe red  c1 blue hidden text"
      expect(out).to include "CVE-2024-1234 ("
      expect(out).to include "Fixed in: 1.2.3"
      expect(out).not_to include "\e[2J"
      expect(out).not_to include "\u{009b}"
      expect(out).not_to include "\u{009d}"
      expect(out).not_to include "\r"
      expect(out).not_to include "\b"
      expect(out).not_to include "pwned"
      expect(out).not_to include "owned"
    end

    it "prints a patched summary section" do
      f = finding(name: "libquicktime", version: "1.2.4",
                  open:    [vuln("CVE-2024-9999", severity: "CRITICAL")],
                  patched: [vuln("CVE-2016-2399"), vuln("GHSA-aaaa-bbbb-cccc")])
      out = render(results([f]))
      expect(out).to include "Found 1 vulnerability in 1 package"
      expect(out).to include "2 resolved by formula patches"
      expect(out).to include "libquicktime: CVE-2016-2399, GHSA-aaaa-bbbb-cccc"
    end

    it "sorts formulae by highest severity first, and vulns within each formula the same" do
      low = finding(name: "aa", version: "1", open: [vuln("CVE-LOW", severity: "LOW")])
      crit = finding(name: "zz", version: "1",
                     open: [vuln("CVE-MED", severity: "MEDIUM"), vuln("CVE-CRIT", severity: "CRITICAL")])
      out = render(results([low, crit]))
      expect(out.index("zz (1)")).to be < out.index("aa (1)")
      expect(out.index("CVE-CRIT")).to be < out.index("CVE-MED")
    end

    it "reports checked and skipped counts" do
      out = render(results([], checked: 5, skipped: 2))
      expect(out).to include "Checking 5 packages for vulnerabilities"
      expect(out).to include "(2 packages skipped - no supported source URL)"
    end
  end

  describe ".json" do
    def render(res)
      out = +""
      described_class.json(res, io: StringIO.new(out))
      JSON.parse(out)
    end

    it "emits an empty array when there are no findings" do
      expect(render(results([]))).to eq []
    end

    it "emits one object per finding with vulnerabilities and patched arrays" do
      f = finding(name: "vim", version: "9.1.2050", tag: "v9.1.2050",
                  repo_url: "https://github.com/vim/vim",
                  open:     [vuln("CVE-2024-1234", severity: "HIGH", summary: "Heap overflow",
                                  aliases: ["GHSA-x"], fixed: ["v10.0.0"])],
                  patched:  [vuln("CVE-2016-2399")])
      data = render(results([f]))
      expect(data).to eq [
        {
          "formula"         => "vim",
          "version"         => "9.1.2050",
          "tag"             => "v9.1.2050",
          "repo_url"        => "https://github.com/vim/vim",
          "vulnerabilities" => [
            { "id" => "CVE-2024-1234", "severity" => "HIGH", "summary" => "Heap overflow",
              "aliases" => ["GHSA-x"], "fixed_versions" => ["v10.0.0"] },
          ],
          "patched"         => [
            { "id" => "CVE-2016-2399", "severity" => "HIGH", "summary" => nil,
              "aliases" => [], "fixed_versions" => [] },
          ],
        },
      ]
    end

    it "emits an empty patched array when nothing is resolved" do
      f = finding(name: "vim", version: "9.1", open: [vuln("CVE-2024-1234")])
      expect(render(results([f])).first["patched"]).to eq []
    end
  end
end
