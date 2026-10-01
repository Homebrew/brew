# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/advisory-match"

RSpec.describe Homebrew::DevCmd::AdvisoryMatch do
  let(:requests) do
    formula("requests") do
      T.bind(self, T.class_of(Formula))
      url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
      head "https://github.com/psf/requests.git"
    end
  end
  let(:reviewed_git_evidence) do
    [{
      "strategy"        => "git",
      "ecosystem"       => "GIT",
      "name"            => "https://github.com/psf/requests",
      "key"             => "https://github.com/psf/requests",
      "subject_version" => "2.31.0",
    }]
  end

  before do
    allow(Formulary).to receive(:enable_factory_cache!)
    allow(Homebrew::Vulns::Repology).to receive_messages(
      load:   Homebrew::Vulns::Repology.new({ "meta" => {}, "formulae" => {} }),
      lookup: {},
    )
    allow(Homebrew::Vulns::CPANSec).to receive(:load).and_return(
      Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {} }),
    )
  end

  it_behaves_like "parseable arguments"

  def cmd_for(*argv, formulae: [requests])
    cmd = described_class.new(argv)
    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return(formulae)
    cmd
  end

  def stub_osv_hit(cve, fixed:, aliases: [])
    allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[{ "id" => cve }], []])
    allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with(cve).and_return(
      { "id" => cve, "aliases" => aliases, "summary" => "s",
        "affected" => [{
          "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
          "ranges"  => [{ "type"   => "ECOSYSTEM",
                          "events" => [{ "introduced" => "0" }, { "fixed" => fixed }] }],
        }] },
    )
  end

  context "with --reconcile-history" do
    let(:matcher) { Homebrew::Vulns::Match.new(strict_upstream: true) }
    let(:result) do
      Homebrew::Vulns::Match::ReconciledHistory.new(state: :range, introduced: "2.20.0", fixed: "2.28.1", reasons: [])
    end
    let(:stored) do
      hit = matcher.advisories_for(requests).fetch(0)
      JSON.parse(JSON.generate(matcher.to_brew_record(requests, hit, now: Time.utc(2020))))
    end

    before do
      stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
      allow(Formulary).to receive(:factory).with(requests.path).and_return(requests)
      allow(matcher).to receive(:reconcile_history).and_return(result)
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
    end

    def reconcile_record
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{stored.fetch("id")}.json")
        original = JSON.generate(stored)
        File.write(path, original)
        overrides = File.join(dir, "overrides.yml")
        File.write(overrides, "{}\n")
        cmd_for("requests", "--output", dir, "--overrides", overrides, "--reconcile-history").run
        yield path, original
      end
    end

    context "when a stored resource is no longer in the formula" do
      let(:resource_data) do
        {
          "id" => "CVE-2024-1234", "aliases" => ["GHSA-certifi"],
          "affected" => [{ "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
                           "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
                             { "introduced" => "0" }, { "fixed" => "1.2" }
                           ] }] }]
        }
      end
      let(:resource_vulnerability) { Homebrew::Vulns::Vulnerability.new(resource_data) }
      let(:resource_evidence) do
        Homebrew::Vulns::Match::Evidence.new(strategy: :registry, ecosystem: "PyPI", name: "certifi",
                                             subject_version: "1.2", key: "pkg:pypi/certifi@1.2", resource: "certifi")
      end
      let(:stored) do
        hit = Homebrew::Vulns::Match::Hit.new(vulnerability: resource_vulnerability, evidence: [resource_evidence])
        JSON.parse(JSON.generate(matcher.to_brew_record(requests, hit, now: Time.utc(2020))))
      end
      let(:old_resource_version) { "1.0" }
      let(:old_formula) do
        resource_version = old_resource_version
        formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/psf/requests/archive/refs/tags/v2.29.0.tar.gz"
          if resource_version
            resource "certifi" do
              url "https://files.pythonhosted.org/packages/11/22/33/certifi-#{resource_version}.tar.gz"
            end
          end
        end
      end

      before do
        allow(matcher).to receive(:reconcile_history).and_call_original
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) do |packages|
          packages.map { |pkg| (pkg[:name] == "certifi") ? [{ "id" => "CVE-2024-1234" }] : [] }
        end
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-1234")
                                                              .and_return(resource_data)
        versions = instance_double(FormulaVersions)
        allow(FormulaVersions).to receive(:new).and_return(versions)
        allow(versions).to receive(:rev_list) { |_, &block| block.call("old", "Formula/r/requests.rb") }
        allow(versions).to receive(:formula_at_revision) { |_, _, &block| block.call(old_formula) }
        allow(Utils).to receive(:popen_read).with(
          "git", "-C", anything, "diff-tree", "--root", "--no-commit-id", "--name-only",
          "--find-renames", "--diff-filter=AR", "-r", "old", safe: true
        ).and_return("Formula/r/requests.rb\n")
      end

      it "reconciles the historical interval even with no current hits" do
        reconcile_record do |path, _|
          expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
            .to eq [{ "introduced" => "2.29.0" }, { "fixed" => "2.31.0" }]
        end
      end

      context "when every historical resource version was fixed" do
        let(:old_resource_version) { "1.3" }

        it "deletes only after proving the resource existed and was never affected" do
          reconcile_record { |path, _| expect(File.exist?(path)).to be false }
        end
      end

      context "when the stored resource identity never existed" do
        let(:old_resource_version) { nil }

        it "holds instead of interpreting absence as proof of never affected" do
          expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
            .to output(/resource_not_found: 1/).to_stdout
        end
      end

      it "holds when fresh queries no longer return the stored advisory" do
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) { |packages| packages.map { [] } }
        expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
          .to output(/resource_not_rediscovered: 1/).to_stdout
      end

      it "does not create records for additional fresh upstream hits" do
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) do |packages|
          packages.map do |pkg|
            (pkg[:name] == "certifi") ? [{ "id" => "CVE-2024-1234" }, { "id" => "CVE-2024-9999" }] : []
          end
        end
        allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-9999")
                                                              .and_return(resource_data.merge(
                                                                            "id" => "CVE-2024-9999", "aliases" => [],
                                                                          ))
        reconcile_record do |path, _|
          expect(Dir.glob(File.join(File.dirname(path), "BREW-*.json"))).to eq [path]
        end
      end

      it "holds if the resource is not witnessed on one platform" do
        linux_formula = formula("requests") do
          T.bind(self, T.class_of(Formula))
          url "https://github.com/psf/requests/archive/refs/tags/v2.29.0.tar.gz"
        end
        versions = instance_double(FormulaVersions)
        allow(FormulaVersions).to receive(:new).and_return(versions)
        allow(versions).to receive(:rev_list) { |_, &block| block.call("old", "Formula/r/requests.rb") }
        allow(versions).to receive(:formula_at_revision) do |_, _, &block|
          block.call(Homebrew::SimulateSystem.simulating_or_running_on_linux? ? linux_formula : old_formula)
        end
        expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
          .to output(/resource_not_found: 1/).to_stdout
      end

      it "keeps unsupported mixed provenance outside fallback discovery" do
        stored.fetch("database_specific").fetch("upstream_evidence").concat(reviewed_git_evidence)
        reconcile_record { |path, original| expect(File.read(path)).to eq original }
      end

      it "leaves generated patch records outside fallback discovery" do
        stored.fetch("database_specific")["source"] = "generated"
        stored.fetch("affected").fetch(0).fetch("ecosystem_specific")["fix"] = "patch"
        reconcile_record { |path, original| expect(File.read(path)).to eq original }
      end

      it "honours a preservation override before supplemental queries or history" do
        overrides = Homebrew::Vulns::AdvisoryOverrides.new({ "requests" => { "advisories" => {
          "GHSA-certifi" => { "preserve_homebrew_ranges" => true },
        } } })
        allow(matcher).to receive(:preserve_homebrew_ranges?) do |name, ids|
          overrides.preserve_homebrew_ranges?(name, ids)
        end
        expect(matcher).not_to receive(:reconcile_history)
        expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)
          .with([{ ecosystem: "PyPI", name: "certifi", version: nil }])
        reconcile_record { |path, original| expect(File.read(path)).to eq original }
      end

      it "honours a skipped formula with a stored removed-resource record" do
        stored
        allow(Homebrew::Vulns::Match).to receive(:new).and_call_original
        Dir.mktmpdir do |dir|
          path = File.join(dir, "#{stored.fetch("id")}.json")
          original = JSON.generate(stored)
          File.write(path, original)
          overrides = File.join(dir, "overrides.yml")
          File.write(overrides, "requests:\n  skip: true\n")
          expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)
          cmd_for("requests", "--output", dir, "--overrides", overrides, "--reconcile-history").run
          expect(File.read(path)).to eq original
        end
      end

      it "holds the formula if the supplemental resource query fails" do
        allow(Homebrew::Vulns::OSV).to receive(:query_batch) do |packages|
          raise Homebrew::Vulns::OSV::Error, "unavailable" if packages.any? { |pkg| pkg[:name] == "certifi" }

          packages.map { [] }
        end
        expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
          .to output(/upstream_unavailable: 1/).to_stdout
      end
    end

    it "requires an explicit overrides file" do
      expect { cmd_for("requests", "--output", "/unused", "--reconcile-history").run }
        .to raise_error(UsageError, /explicit.*--overrides/)
    end

    it "reports distinct failed revisions separately from platform loads and held records" do
      failures = [:arm, :intel].map do |arch|
        Homebrew::Vulns::History::LoadFailure.new(
          formula: "requests", revision: "abc123", path: "Formula/r/requests.rb",
          platform: "linux/#{arch}", error_class: "NoMethodError", message: "missing DSL"
        )
      end
      allow(matcher).to receive(:history_load_failures).and_return(failures)
      command = cmd_for("--verbose")

      expect { command.report_history_load_failures(matcher) }.to output(
        "  History loads: 1 failed formula revisions across 1 formulae (2 platform loads)\n    " \
        "requests: abc123:Formula/r/requests.rb [linux/arm] NoMethodError: missing DSL\n    " \
        "requests: abc123:Formula/r/requests.rb [linux/intel] NoMethodError: missing DSL\n",
      ).to_stdout
    end

    it "keeps failed-load details out of non-verbose summaries" do
      allow(matcher).to receive(:history_load_failures).and_return([
        Homebrew::Vulns::History::LoadFailure.new(
          formula: "requests", revision: "abc123", path: "Formula/r/requests.rb",
          platform: "linux/arm", error_class: "NoMethodError", message: "missing DSL"
        ),
      ])

      expect { cmd_for.report_history_load_failures(matcher) }
        .to output("  History loads: 1 failed formula revisions across 1 formulae (1 platform loads)\n").to_stdout
    end

    it "reconciles a CPANSA fallback without an upstream hold after a supplemental 404" do
      perl = formula("perl-example") do
        T.bind(self, T.class_of(Formula))
        url "https://cpan.metacpan.org/authors/id/X/XY/XYZ/Example-2.0.tar.gz"
      end
      allow(Homebrew::Vulns::CPANSec).to receive(:load).and_return(
        Homebrew::Vulns::CPANSec.new({ "meta" => {}, "dists" => {
          "Example" => { "advisories" => [{ "id" => "CPANSA-Example-1", "cves" => ["CVE-2022-4988"],
            "affected_versions" => ["<1.0"], "fixed_versions" => [">=1.0"] }] },
        } }),
      )
      allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[]])
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability)
        .and_raise(Homebrew::Vulns::OSV::NotFoundError, "404")
      allow(Formulary).to receive(:factory).with(perl.path).and_return(perl)
      hit = matcher.advisories_for(perl).fetch(0)
      record = matcher.to_brew_record(perl, hit, now: Time.utc(2020))
      allow(matcher).to receive(:reconcile_history).and_return(result.with(state: :never_affected))

      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{record.fetch(:id)}.json")
        File.write(path, JSON.generate(record))
        overrides = File.join(dir, "overrides.yml")
        File.write(overrides, "{}\n")
        expect do
          cmd_for("perl-example", "--output", dir, "--overrides", overrides,
                  "--reconcile-history", formulae: [perl]).run
        end.to output(/Reconciliation: 1 deleted; 0 matched records not revisited\n\z/).to_stdout
        expect([File.exist?(path), Homebrew.failed?]).to eq [false, false]
      end
    end

    it "loads a real preservation override before any history walk" do
      stored
      allow(Homebrew::Vulns::Match).to receive(:new).and_call_original
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{stored.fetch("id")}.json")
        original = JSON.generate(stored)
        File.write(path, original)
        overrides = File.join(dir, "overrides.yml")
        File.write(overrides, "requests:\n  advisories:\n    CVE-2024-1234:\n      preserve_homebrew_ranges: true\n")
        expect { cmd_for("requests", "--output", dir, "--overrides", overrides, "--reconcile-history").run }
          .to output(/0 history walks.*preserved: 1/m).to_stdout
        expect(File.read(path)).to eq original
      end
    end

    it "loads and walks distinct formula views under each platform" do
      walked = []
      allow(Formulary).to receive(:factory).with(requests.path) do
        Formulary.from_contents("requests", requests.path, <<~RUBY)
          class Requests < Formula
            url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
            head "https://github.com/psf/requests.git"
          end
        RUBY
      end
      allow(matcher).to receive(:reconcile_history) do |view, _hit|
        walked << [Homebrew::SimulateSystem.current_os, Homebrew::SimulateSystem.current_arch, view.object_id]
        result
      end
      reconcile_record do |_path, _original|
        expect([walked.map(&:last).uniq.length, walked.map { |os, arch, _| [os == :linux, arch] }]).to eq(
          [4, [[false, :arm], [false, :intel], [true, :arm], [true, :intel]]],
        )
      end
    end

    it "holds failed upstream fetches instead of deleting a partially matched record" do
      stored
      allow(Homebrew::Vulns::Match).to receive(:new).and_call_original
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).and_raise(Homebrew::Vulns::OSV::ApiError, "unavailable")
      expect do
        reconcile_record do |path, original|
          expect([File.read(path), Homebrew.failed?]).to eq [original, false]
        end
      end
        .to output(/upstream_unavailable: 1/).to_stdout
    end

    it "holds the formula when a later platform cannot fetch upstream records" do
      stored
      allow(matcher).to receive(:advisories_for).and_raise(Homebrew::Vulns::OSV::ApiError, "503")
      expect do
        reconcile_record do |path, original|
          expect([File.read(path), Homebrew.failed?]).to eq [original, false]
        end
      end
        .to output(/upstream_unavailable: 1/).to_stdout
    end

    it "shrinks a matched terminal range while preserving every other field" do
      reconcile_record do |path, _original|
        updated = JSON.parse(File.read(path))
        expected = stored.deep_dup
        expected["modified"] = updated.fetch("modified")
        expected.fetch("affected").fetch(0)["ranges"] = [{ "type" => "ECOSYSTEM", "events" => [
          { "introduced" => "2.20.0" }, { "fixed" => "2.28.1" }
        ] }]
        expect(updated).to eq expected
      end
    end

    it "deletes a matched record only after all platforms prove it was never affected" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(state: :never_affected))
      reconcile_record { |path, _| expect(File).not_to exist(path) }
    end

    it "leaves a corrected record byte-identical on a later reconciliation" do
      allow(Time).to receive(:now).and_return(Time.utc(2025))
      reconcile_record do |path, _original|
        corrected = File.read(path)
        dir = File.dirname(path)
        allow(Time).to receive(:now).and_return(Time.utc(2026))

        expect do
          cmd_for("requests", "--output", dir, "--overrides", File.join(dir, "overrides.yml"),
                  "--reconcile-history").run
        end.to output(/0 records written.*1 unchanged/).to_stdout
        expect(File.read(path)).to eq corrected
      end
    end

    it "does not recreate a deleted record on a later reconciliation" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(state: :never_affected))
      reconcile_record do |path, _original|
        dir = File.dirname(path)
        expect(matcher).not_to receive(:reconcile_history)

        cmd_for("requests", "--output", dir, "--overrides", File.join(dir, "overrides.yml"),
                "--reconcile-history").run
        expect(File).not_to exist(path)
      end
    end

    it "does not reconcile a generated record" do
      stored.fetch("database_specific")["source"] = "generated"
      expect(matcher).not_to receive(:reconcile_history)
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "does not reconcile a patch fix even if its source is matched" do
      stored.fetch("affected").fetch(0).fetch("ecosystem_specific")["fix"] = "patch"
      expect(matcher).not_to receive(:reconcile_history)
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "leaves a preserved record byte-identical" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(state: :preserved))
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "leaves unresolved history byte-identical" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(state:   :unresolved,
                                                                           reasons: [:subject_changed]))
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "leaves a disappeared current match unchanged" do
      stored
      allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[], []])
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "does not create new records" do
      Dir.mktmpdir do |dir|
        overrides = File.join(dir, "overrides.yml")
        File.write(overrides, "{}\n")
        cmd_for("requests", "--output", dir, "--overrides", overrides, "--reconcile-history").run
        expect(Dir.glob(File.join(dir, "BREW-*.json"))).to be_empty
      end
    end

    it "rejects changed stored provenance before walking history" do
      stored.fetch("database_specific").fetch("upstream_evidence").fetch(0)["name"] = "another-package"
      expect(matcher).not_to receive(:reconcile_history)
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "does not expand an existing affected interval" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(fixed: "2.32.0"))
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "classifies an open reconciliation result as reopened" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(fixed: nil))
      expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
        .to output(/reopened: 1/).to_stdout
    end

    it "distinguishes an invalid interval from range expansion" do
      allow(matcher).to receive(:reconcile_history).and_return(result.with(introduced: "2.28.1"))
      expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
        .to output(/invalid_interval: 1/).to_stdout
    end

    it "reports a generated alias as protected" do
      stored.fetch("database_specific")["source"] = "generated"
      expect { reconcile_record { |path, original| expect(File.read(path)).to eq original } }
        .to output(/alias_protected: 1/).to_stdout
    end

    it "does not replace multiple intervals" do
      stored.fetch("affected").fetch(0).fetch("ranges").fetch(0).fetch("events") << { "introduced" => "2.32.0" }
      expect(matcher).not_to receive(:reconcile_history)
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "holds differing platform histories" do
      allow(matcher).to receive(:reconcile_history) do
        Homebrew::Vulns::Match::ReconciledHistory.new(
          state:      :range,
          introduced: "2.20.0",
          fixed:
            if Homebrew::SimulateSystem.simulating_or_running_on_linux?
              "2.29.0"
            else
              "2.28.1"
            end,
          reasons:    [],
        )
      end
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "holds a match missing from an alternate platform" do
      stored
      allow(Homebrew::Vulns::OSV).to receive(:query_batch) do
        Homebrew::SimulateSystem.simulating_or_running_on_linux? ? [[], []] : [[{ "id" => "CVE-2024-1234" }], []]
      end
      reconcile_record { |path, original| expect(File.read(path)).to eq original }
    end

    it "does not overwrite a record edited during the history walk" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{stored.fetch("id")}.json")
        File.write(path, JSON.generate(stored))
        overrides = File.join(dir, "overrides.yml")
        File.write(overrides, "{}\n")
        edited = stored.merge("summary" => "Reviewed concurrently")
        allow(matcher).to receive(:reconcile_history) do
          File.write(path, JSON.generate(edited))
          result
        end
        cmd_for("requests", "--output", dir, "--overrides", overrides, "--reconcile-history").run
        expect(JSON.parse(File.read(path))).to eq edited
      end
    end
  end

  it "updates one existing matched alias without creating a canonical duplicate" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      File.write(alias_path, JSON.generate({
        "id"                => "BREW-requests-GHSA-old",
        "summary"           => "stale",
        "upstream"          => ["GHSA-old"],
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.28.1" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.28.1" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      cmd_for("requests", "--output", dir, "--no-history").run

      files = Dir.glob(File.join(dir, "*.json"))
      refreshed = JSON.parse(File.read(alias_path))
      expect([files, refreshed.values_at("id", "summary", "upstream")]).to eq [
        [alias_path],
        ["BREW-requests-GHSA-old", "s", ["GHSA-old", "CVE-2024-1234"]],
      ]
    end
  end

  it "fails closed when an alias family already has multiple matched records" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      originals = ["GHSA-old", "PYSEC-old"].to_h do |id|
        path = File.join(dir, "BREW-requests-#{id}.json")
        record = {
          "id"                => "BREW-requests-#{id}",
          "summary"           => id,
          "upstream"          => [id, "GHSA-old"],
          "affected"          => [{
            "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.28.1" }
            ] }],
          }],
          "database_specific" => { "source" => "matched" },
        }
        File.write(path, JSON.generate(record))
        [path, record]
      end

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/multiple alias records/).to_stderr
      actual = originals.to_h { |path, _| [path, JSON.parse(File.read(path))] }
      expect([actual, Homebrew.failed?]).to eq [originals, true]
    end
  end

  it "uses a terminal alias to decide whether reintroduction history is required" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_reintroduced_version).and_return("2.31.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      File.write(alias_path, JSON.generate({
        "id"                => "BREW-requests-GHSA-old",
        "upstream"          => ["GHSA-old"],
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/1 history walks/).to_stdout
      expect(JSON.parse(File.read(alias_path)).dig("affected", 0, "ranges", 0, "events")).to eq([
        { "introduced" => "0" }, { "fixed" => "2.30.0" }, { "introduced" => "2.31.0" }
      ])
    end
  end

  it "protects a generated alias without emitting a matched duplicate" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      generated_path = File.join(dir, "BREW-requests-GHSA-old.json")
      generated = {
        "id"                => "BREW-requests-GHSA-old",
        "upstream"          => ["GHSA-old"],
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ecosystem_specific" => { "fix" => "patch" },
        }],
        "database_specific" => { "source" => "generated" },
      }
      File.write(generated_path, JSON.generate(generated))

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/1 generated left as-is/).to_stdout
      expect([
        JSON.parse(File.read(generated_path)),
        File.exist?(File.join(dir, "BREW-requests-CVE-2024-1234.json")),
      ]).to eq [generated, false]
    end
  end

  it "rejects overlapping alias groups before writing either family" do
    Dir.mktmpdir do |dir|
      shared_path = File.join(dir, "BREW-requests-GHSA-shared.json")
      File.write(shared_path, JSON.generate({
        "id"                => "BREW-requests-GHSA-shared",
        "upstream"          => ["GHSA-shared"],
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
        }],
        "database_specific" => { "source" => "matched" },
      }))
      emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(dir, verbose: false, close_open_ranges: false)

      errors = emitter.prepare_aliases("requests", {
        "BREW-requests-CVE-one" => ["BREW-requests-CVE-one", "BREW-requests-GHSA-shared"],
        "BREW-requests-CVE-two" => ["BREW-requests-CVE-two", "BREW-requests-GHSA-shared"],
      })

      expect(errors.join("\n")).to include("identity also belongs")
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-one.json"))
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-two.json"))
    end
  end

  it "fails closed when an alias filename and record id disagree" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      conflicting = {
        "id"                => "BREW-requests-GHSA-other",
        "upstream"          => ["GHSA-old"],
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
        }],
        "database_specific" => { "source" => "matched" },
      }
      File.write(alias_path, JSON.generate(conflicting))

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/mismatched id/).to_stderr
      expect(JSON.parse(File.read(alias_path))).to eq conflicting
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-2024-1234.json"))
      expect(Homebrew.failed?).to be true
    end
  end

  it "fails closed when an alias database_specific value is not an object" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      existing = {
        "id"                => "BREW-requests-GHSA-old",
        "upstream"          => ["GHSA-old", "CVE-2024-1234"],
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
        }],
        "database_specific" => "bad",
      }
      File.write(alias_path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/unsupported source/).to_stderr
      expect(JSON.parse(File.read(alias_path))).to eq existing
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-2024-1234.json"))
      expect(Homebrew.failed?).to be true
    end
  end

  it "fails closed when an alias package value is not an object" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      existing = {
        "id"                => "BREW-requests-GHSA-old",
        "upstream"          => ["GHSA-old", "CVE-2024-1234"],
        "affected"          => [{
          "package" => "bad",
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
        }],
        "database_specific" => { "source" => "matched" },
      }
      File.write(alias_path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/unsupported affected entries/).to_stderr
      expect(JSON.parse(File.read(alias_path))).to eq existing
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-2024-1234.json"))
      expect(Homebrew.failed?).to be true
    end
  end

  it "fails closed when an alias has multiple affected entries" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      alias_path = File.join(dir, "BREW-requests-GHSA-old.json")
      existing = {
        "id"                => "BREW-requests-GHSA-old",
        "upstream"          => ["GHSA-old", "CVE-2024-1234"],
        "affected"          => [
          {
            "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.27.0" }
            ] }],
          },
          {
            "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
            "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "2.27.1" }, { "fixed" => "2.28.0" }
            ] }],
          },
        ],
        "database_specific" => { "source" => "matched" },
      }
      File.write(alias_path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/unsupported affected entries/).to_stderr
      expect(JSON.parse(File.read(alias_path))).to eq existing
      expect(File).not_to exist(File.join(dir, "BREW-requests-CVE-2024-1234.json"))
      expect(Homebrew.failed?).to be true
    end
  end

  it "writes matched records to --output=<dir> with merge_existing semantics" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/1 records written/).to_stdout

      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      record = JSON.parse(File.read(path))
      expect(record.dig("affected", 0, "package"))
        .to eq("ecosystem" => "Homebrew", "name" => "requests", "purl" => "pkg:brew/requests")
      expect(record.dig("affected", 0, "ranges", 0, "events", 1))
        .to eq("fixed" => requests.pkg_version.to_s)
      expect(record.dig("database_specific", "source")).to eq "matched"
      expect(record.dig("database_specific", "strategy")).to eq "git"

      # A second run with the same output should report 0 written / 1 unchanged.
      expect { cmd_for("requests", "--output", dir, "--no-history").run }
        .to output(/0 records written to #{Regexp.escape(dir)} \(1 unchanged, 0 generated/).to_stdout
    end
  end

  describe "range basis identities" do
    let(:dir) { Dir.mktmpdir }
    let(:emitter) { Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(dir, verbose: false, close_open_ranges: true) }

    after { FileUtils.remove_entry(dir) }

    def basis_for(evidence, ecosystem_specific = {})
      emitter.range_basis({
        affected:          [{ ecosystem_specific: }],
        database_specific: { upstream_evidence: evidence },
      })
    end

    it "detects distro, CPANSA, Git, scoped package and checkability drift alongside registry evidence" do
      cases = [
        [{ strategy: :distro, key: "Debian:13/foo" }, { strategy: :distro, key: "Ubuntu:24.04/bar" }],
        [{ strategy: :cpansa, key: "pkg:cpan/Foo@1" }, { strategy: :cpansa, key: "pkg:cpan/Bar@1" }],
        [{ strategy: :git, key: "https://github.com/o/old" },
         { strategy: :git, key: "https://github.com/o/new" }],
        [{ strategy: :registry, key: "pkg:npm/@scope-a/name@1" },
         { strategy: :registry, key: "pkg:npm/@scope-b/other@1" }],
        [{ strategy: :registry, key: "pkg:pypi/x@1", subject_version: nil },
         { strategy: :registry, key: "pkg:pypi/x@1", subject_version: "1" }],
      ]
      outcomes = cases.map do |before, after|
        primary = { strategy: :registry, key: "pkg:pypi/primary@1" }

        basis_for([primary, before]) != basis_for([primary, after])
      end
      expect(outcomes).to eq [true, true, true, true, true]
    end

    it "detects removal of a secondary resource even when the deciding resource is unchanged" do
      deciding = { strategy: :registry, key: "pkg:pypi/x@1", resource: "first" }
      secondary = { strategy: :registry, key: "pkg:pypi/y@1", resource: "second" }
      eco = { resource_purl: "pkg:pypi/x@1" }

      expect(basis_for([deciding, secondary], eco)).not_to eq basis_for([deciding], eco)
    end

    it "retains the multiplicity of separate resources shipping the same package" do
      first = { strategy: :registry, key: "pkg:pypi/x@1", resource: "first" }
      second = { strategy: :registry, key: "pkg:pypi/x@2", resource: "second" }

      expect(basis_for([first, second])).not_to eq basis_for([first])
    end

    it "ignores evidence order, duplicate provenance, resource labels and package versions" do
      first = { strategy: :registry, key: "upstream:pkg:pypi/x@1", subject_version: "1" }
      second = { strategy: :cpansa, key: "pkg:cpan/Foo@1", subject_version: "1", resource: "old" }

      expect(basis_for([first, second, first])).to eq basis_for([
        second.merge(key: "pkg:cpan/Foo@2", subject_version: "2", resource: "new"),
        first.merge(key: "upstream:pkg:pypi/x@2", subject_version: "2"),
      ])
    end

    it "detects removal of an upstream fixed threshold" do
      expect(basis_for([], { upstream_fixed_in: "1" })).not_to eq basis_for([])
    end

    it "uses runtime identities across CPAN author transfers and equivalent PyPI spellings" do
      identities = [
        ["cpansa", "CPAN", "Foo", "pkg:cpan/ABCD/Foo@1.0", "pkg:cpan/EFGH/Foo@1.1"],
        ["registry", "PyPI", "foo-bar", "pkg:pypi/foo.bar@1.0", "pkg:pypi/foo-bar@1.1"],
      ]
      outcomes = identities.map do |strategy, ecosystem, name, previous_key, current_key|
        row = { strategy:, ecosystem:, name:, resource: "dependency", subject_version: "1.0" }
        basis_for([row.merge(key: previous_key)], { resource_purl: previous_key }) ==
          basis_for([row.merge(key: current_key)], { resource_purl: current_key })
      end

      expect(outcomes).to eq [true, true]
    end
  end

  describe "generated alias ownership" do
    let(:dir) { Dir.mktmpdir }
    let(:emitter) { Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(dir, verbose: false, close_open_ranges: true) }

    after { FileUtils.remove_entry(dir) }

    it "protects generated families with one or more generated or matched siblings" do
      cases = [["generated", "matched"], ["generated", "generated"], ["generated", "matched", "matched"]]
      outcomes = cases.map do |sources|
        Dir.mktmpdir do |scenario_dir|
          owner = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(
            scenario_dir, verbose: false, close_open_ranges: true
          )
          paths = sources.each_with_index.map do |source, index|
            path = File.join(scenario_dir, "BREW-requests-GHSA-#{index}.json")
            File.write(path, JSON.generate({
              id:                "BREW-requests-GHSA-#{index}",
              upstream:          ["CVE-2024-1234"],
              affected:          [{ package: { ecosystem: "Homebrew", name: "requests" } }],
              database_specific: { source: },
            }))
            path
          end
          originals = paths.map { |path| File.read(path) }
          errors = owner.prepare_aliases("requests", {
            "BREW-requests-CVE-2024-1234" => ["BREW-requests-CVE-2024-1234"],
          })

          [errors, owner.alias_protected?("BREW-requests-CVE-2024-1234"),
           owner.alias_target_paths("BREW-requests-CVE-2024-1234"), paths.map { |path| File.read(path) }] ==
            [[], true, [], originals]
        end
      end
      expect(outcomes).to eq [true, true, true]
    end

    it "rejects a generated record affecting another formula before granting ownership" do
      File.write(File.join(dir, "BREW-requests-CVE-2024-1234.json"), JSON.generate({
        id:                "BREW-requests-CVE-2024-1234",
        affected:          [{ package: { ecosystem: "Homebrew", name: "another-formula" } }],
        database_specific: { source: "generated" },
      }))

      expect(emitter.prepare_aliases("requests", {
        "BREW-requests-CVE-2024-1234" => ["BREW-requests-CVE-2024-1234"],
      })).to include(/unsupported affected entries/)
    end
  end

  describe "range basis migration" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "BREW-requests-CVE-2024-1234.json") }
    let(:existing) do
      {
        id:                "BREW-requests-CVE-2024-1234",
        affected:          [{
          package: { ecosystem: "Homebrew", name: "requests" },
          ranges:  [{ type: "ECOSYSTEM", events: [{ introduced: "0" }, { fixed: "2.28.1" }] }],
        }],
        database_specific: { source: "matched" },
      }
    end

    before { stub_osv_hit("CVE-2024-1234", fixed: "2.28.1") }
    after { FileUtils.remove_entry(dir) }

    it "rechecks history for a legacy terminal record and adopts matching provenance" do
      File.write(path, JSON.generate(existing))
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_fixed_version).and_return("2.28.1")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

      cmd_for("requests", "--output", dir, "--new-history").run

      refreshed = JSON.parse(File.read(path))
      expect([refreshed.dig("affected", 0, "ranges"),
              refreshed.dig("database_specific", "upstream_evidence")&.empty?])
        .to eq [JSON.parse(JSON.generate(existing.dig(:affected, 0, :ranges))), false]
    end

    it "repairs legacy missing, empty or invalid ranges after verifying history" do
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive_messages(first_fixed_version: "2.28.1", first_introduced_version: "2.27.0")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      cases = [nil, [], [{ type: "ECOSYSTEM", events: [] }]]
      outcomes = cases.map do |ranges|
        record = existing.deep_dup
        record[:affected].first[:ranges] = ranges
        File.write(path, JSON.generate(record))

        cmd_for("requests", "--output", dir, "--new-history").run

        JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events") ==
          [{ "introduced" => "2.27.0" }, { "fixed" => "2.28.1" }]
      end

      expect(outcomes).to eq [true, true, true]
    end

    it "derives introductions before repairing affected records with changed provenance" do
      stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_introduced_version).and_return("2.30.0")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      outcomes = [nil, [], [{ type: "ECOSYSTEM", events: [] }]].map do |ranges|
        record = existing.deep_dup
        if ranges
          record[:affected].first[:ranges] = ranges
        else
          record[:affected].first.delete(:ranges)
        end
        File.write(path, JSON.generate(record))

        output = capture_stdout { cmd_for("requests", "--output", dir, "--new-history").run }
        refreshed = JSON.parse(File.read(path))
        [refreshed.dig("affected", 0, "ranges", 0, "events"),
         refreshed.dig("database_specific", "upstream_evidence"), output.include?("1 history walks")]
      end

      expect(outcomes).to all(eq([[{ "introduced" => "2.30.0" }], reviewed_git_evidence, true]))
    end

    it "preserves affected records with changed provenance when introduction history is unavailable" do
      stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_introduced_version).and_return(:history_unavailable)
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      outcomes = [nil, [], [{ type: "ECOSYSTEM", events: [] }]].map do |ranges|
        record = existing.deep_dup
        if ranges
          record[:affected].first[:ranges] = ranges
        else
          record[:affected].first.delete(:ranges)
        end
        File.write(path, JSON.generate(record))
        original = File.read(path)

        output = capture_stdout { cmd_for("requests", "--output", dir, "--new-history").run }
        [File.read(path) == original, output.include?("1 history walks, 1 history-unavailable skips")]
      end

      expect(outcomes).to all(eq([true, true]))
    end

    it "leaves a legacy terminal record unchanged when recomputed ranges disagree" do
      File.write(path, JSON.generate(existing))
      original = File.read(path)
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_fixed_version).and_return("2.29.0")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      output = capture_stdout { cmd_for("requests", "--output", dir, "--new-history").run }

      expect([File.read(path), Homebrew.failed?, output.include?("1 range-basis skips")])
        .to eq [original, true, true]
    end

    it "cannot migrate a terminal record using today's version with --no-history" do
      existing[:affected].first[:ranges].first[:events].last[:fixed] = requests.pkg_version.to_s
      File.write(path, JSON.generate(existing))
      original = File.read(path)

      cmd_for("requests", "--output", dir, "--no-history").run

      expect([File.read(path), Homebrew.failed?]).to eq [original, true]
    end

    it "does not adopt provenance when the forced history walk is unavailable" do
      File.write(path, JSON.generate(existing))
      original = File.read(path)
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_fixed_version).and_return(:history_unavailable)
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      output = capture_stdout { cmd_for("requests", "--output", dir, "--new-history").run }

      expect([File.read(path), output.include?("1 history-unavailable skips")]).to eq [original, true]
    end

    it "does not treat a fixed-threshold override as proof of an existing terminal range" do
      existing[:database_specific][:upstream_evidence] = reviewed_git_evidence
      existing[:affected].first[:ecosystem_specific] = { upstream_fixed_in: "2.28.1" }
      File.write(path, JSON.generate(existing))
      original = File.read(path)
      overrides_path = File.join(dir, "overrides.yml")
      File.write(overrides_path, <<~YAML)
        requests:
          advisories:
            CVE-2024-1234:
              upstream_fixed_in: "2.29.0"
      YAML
      overrides = Homebrew::Vulns::AdvisoryOverrides.from_file(Pathname(overrides_path))
      matcher = Homebrew::Vulns::Match.new(overrides:)
      allow(matcher).to receive(:first_fixed_version).and_return("2.28.1")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

      cmd_for("requests", "--output", dir, "--new-history", "--overrides", overrides_path).run

      expect([File.read(path), Homebrew.failed?]).to eq [original, true]
    end

    it "accepts a fixed-threshold override after the record's ranges and provenance are reviewed together" do
      existing[:database_specific][:upstream_evidence] = reviewed_git_evidence
      existing[:affected].first[:ecosystem_specific] = { upstream_fixed_in: "2.29.0" }
      File.write(path, JSON.generate(existing))
      overrides_path = File.join(dir, "overrides.yml")
      File.write(overrides_path, <<~YAML)
        requests:
          advisories:
            CVE-2024-1234:
              upstream_fixed_in: "2.29.0"
      YAML

      cmd_for("requests", "--output", dir, "--new-history", "--overrides", overrides_path).run

      refreshed = JSON.parse(File.read(path))
      expect([refreshed.dig("affected", 0, "ecosystem_specific", "upstream_fixed_in"),
              refreshed.dig("affected", 0, "ranges", 0, "events").last, Homebrew.failed?])
        .to eq ["2.29.0", { "fixed" => "2.28.1" }, false]
    end

    it "adopts a legacy open record when the candidate has exactly the same range" do
      stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
      existing[:affected].first[:ranges].first[:events].pop
      File.write(path, JSON.generate(existing))

      cmd_for("requests", "--output", dir, "--new-history").run

      expect(JSON.parse(File.read(path)).dig("database_specific", "upstream_evidence")).not_to be_nil
    end

    it "rejects a fixed boundary preceding a single reviewed open introduction" do
      existing[:affected].first[:ranges].first[:events] = [{ introduced: "2.29.0" }]
      File.write(path, JSON.generate(existing))
      original = File.read(path)
      matcher = Homebrew::Vulns::Match.new
      allow(matcher).to receive(:first_fixed_version).and_return("2.28.1")
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/fixed 2\.28\.1 does not follow its reviewed range/).to_stderr
      expect([File.read(path), Homebrew.failed?]).to eq [original, true]
    end
  end

  it "fails closed when a reviewed matched range basis changes" do
    incompatible = [
      [
        { "resource" => "multipart", "resource_purl" => "pkg:pypi/fastapi@0.109.1",
          "upstream_fixed_in" => "0.109.1" },
        { resource: "multipart", resource_purl: "pkg:pypi/python-multipart@0.0.20",
          upstream_fixed_in: "0.0.7" },
      ],
      [
        { "resource" => "marshmallow", "resource_purl" => "pkg:pypi/marshmallow@3.26.2",
          "upstream_fixed_in" => "3.26.2" },
        { resource: "marshmallow", resource_purl: "pkg:pypi/marshmallow@4.3.1",
          upstream_fixed_in: "4.1.2" },
      ],
      [
        {},
        { resource: "multipart", resource_purl: "pkg:pypi/python-multipart@0.0.20",
          upstream_fixed_in: "0.0.7" },
      ],
    ]

    outcomes = incompatible.map do |existing_basis, incoming_basis|
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
        existing = {
          "id"                => "BREW-requests-CVE-2024-1234",
          "summary"           => "reviewed",
          "upstream"          => ["CVE-2024-1234"],
          "affected"          => [{
            "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
            "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
              { "introduced" => "0" }, { "fixed" => "2.28.1" }
            ] }],
            "ecosystem_specific" => existing_basis,
          }],
          "database_specific" => { "source" => "matched" },
        }
        File.write(path, JSON.generate(existing))
        emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(
          dir, verbose: false, close_open_ranges: true
        )
        errors = emitter.prepare_aliases("requests", {
          "BREW-requests-CVE-2024-1234" => ["BREW-requests-CVE-2024-1234"],
        })

        emitter.emit({
          id:                "BREW-requests-CVE-2024-1234",
          summary:           "incoming",
          upstream:          ["CVE-2024-1234"],
          affected:          [{
            package:            { ecosystem: "Homebrew", name: "requests" },
            ranges:             [{ type: "ECOSYSTEM", events: [
              { introduced: "0" }, { fixed: "3.0" }
            ] }],
            ecosystem_specific: incoming_basis,
          }],
          database_specific: { source: "matched" },
        })
        errors.empty? && JSON.parse(File.read(path)) == existing && Homebrew.failed?
      end
    end

    expect(outcomes).to eq [true, true, true]
  end

  it "fails closed when a reviewed primary package identity changes" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      existing = {
        "id"                => "BREW-requests-CVE-2024-1234",
        "summary"           => "reviewed",
        "upstream"          => ["CVE-2024-1234"],
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.28.1" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "1.0" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => [{
            "strategy" => "registry",
            "key"      => "pkg:pypi/old-package@2.0",
          }],
        },
      }
      File.write(path, JSON.generate(existing))
      emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(
        dir, verbose: false, close_open_ranges: true
      )
      emitter.prepare_aliases("requests", {
        "BREW-requests-CVE-2024-1234" => ["BREW-requests-CVE-2024-1234"],
      })

      expect do
        emitter.emit({
          id:                "BREW-requests-CVE-2024-1234",
          summary:           "incoming",
          upstream:          ["CVE-2024-1234"],
          affected:          [{
            package:            { ecosystem: "Homebrew", name: "requests" },
            ranges:             [{ type: "ECOSYSTEM", events: [
              { introduced: "0" }, { fixed: "3.0" }
            ] }],
            ecosystem_specific: { upstream_fixed_in: "1.0" },
          }],
          database_specific: {
            source:            "matched",
            upstream_evidence: [{ strategy: :registry, key: "pkg:pypi/new-package@2.0" }],
          },
        })
      end.to output(/range basis changed/).to_stderr
      expect([JSON.parse(File.read(path)), Homebrew.failed?]).to eq [existing, true]
    end
  end

  it "accepts resource version and label changes for the same reviewed package" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "summary"           => "reviewed",
        "upstream"          => ["CVE-2024-1234"],
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.28.1" }
          ] }],
          "ecosystem_specific" => {
            "resource"          => "old-label",
            "resource_purl"     => "pkg:pypi/python-multipart@0.0.7",
            "upstream_fixed_in" => "0.0.7",
          },
        }],
        "database_specific" => { "source" => "matched" },
      }))
      emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(
        dir, verbose: false, close_open_ranges: true
      )
      emitter.prepare_aliases("requests", {
        "BREW-requests-CVE-2024-1234" => ["BREW-requests-CVE-2024-1234"],
      })

      emitter.emit({
        id:                "BREW-requests-CVE-2024-1234",
        summary:           "incoming",
        upstream:          ["CVE-2024-1234"],
        affected:          [{
          package:            { ecosystem: "Homebrew", name: "requests" },
          ranges:             [{ type: "ECOSYSTEM", events: [
            { introduced: "0" }, { fixed: "3.0" }
          ] }],
          ecosystem_specific: {
            resource:          "new-label",
            resource_purl:     "pkg:pypi/python-multipart@0.0.20",
            upstream_fixed_in: "0.0.7",
          },
        }],
        database_specific: { source: "matched" },
      })

      refreshed = JSON.parse(File.read(path))
      expect([
        refreshed["summary"],
        refreshed.dig("affected", 0, "ecosystem_specific", "resource"),
        refreshed.dig("affected", 0, "ranges", 0, "events").last,
      ]).to eq ["incoming", "new-label", { "fixed" => "2.28.1" }]
    end
  end

  it "skips history for existing terminal records with unchanged provenance under --new-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      record = {
        "schema_version"    => Homebrew::Vulns::OsvExport::SCHEMA_VERSION,
        "id"                => "BREW-requests-CVE-2024-1234",
        "modified"          => "2026-01-01T00:00:00Z",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.28.1" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.28.1" },
        }],
        "database_specific" => { "source" => "matched", "upstream_evidence" => reviewed_git_evidence },
      }
      File.write(path, JSON.generate(record))

      matcher = Homebrew::Vulns::Match.new
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
      expect(matcher).not_to receive(:first_fixed_version)

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/0 history walks/).to_stdout
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events", 1))
        .to eq("fixed" => "2.28.1")
    end
  end

  it "uses both historical boundaries for a new record with --new-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return("2.28.1")
    expect(matcher).to receive(:first_introduced_version).with(requests, anything, first_fixed: "2.28.1")
                                                         .and_return("2.27.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/2 history walks/).to_stdout
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "2.27.0" }, { "fixed" => "2.28.1" }])
    end
  end

  it "repairs mixed ranges using an initial interval without reopening reviewed terminal ranges" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    allow(matcher).to receive_messages(first_fixed_version: "2.28.1", first_introduced_version: "2.27.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      reviewed = [{ "introduced" => "2.20.0" }, { "fixed" => "2.26.0" }]
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [
            { "type" => "ECOSYSTEM", "events" => reviewed },
            { "type" => "ECOSYSTEM", "events" => [] },
          ],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.28.1" },
        }],
        "database_specific" => { "source" => "matched", "upstream_evidence" => reviewed_git_evidence },
      }))

      cmd_for("requests", "--output", dir, "--new-history").run

      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges")).to eq [
        { "type" => "ECOSYSTEM", "events" => reviewed },
        { "type" => "ECOSYSTEM", "events" => [{ "introduced" => "2.27.0" }, { "fixed" => "2.28.1" }] },
      ]
    end
  end

  it "skips a new record when formula history is unavailable" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return(:history_unavailable)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      expect do
        expect { cmd_for("requests", "--output", dir, "--new-history").run }
          .to output(/formula history is unavailable; skipping automatic update/).to_stderr
      end.to output(/1 history-unavailable skips.*Unavailable history by formula:\n    requests: 1/m).to_stdout
      expect(Dir.glob(File.join(dir, "*.json"))).to be_empty
    end
  end

  it "does not emit a fixed record when its introduction cannot be established" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    allow(matcher).to receive_messages(first_fixed_version: "2.28.1", first_introduced_version: :history_unavailable)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      expect do
        expect { cmd_for("requests", "--output", dir, "--new-history").run }
          .to output(/affected introduction cannot be established; skipping automatic update/).to_stderr
      end.to output(/2 history walks, 1 history-unavailable skips/).to_stdout
      expect(Dir.glob(File.join(dir, "*.json"))).to be_empty
    end
  end

  it "does not emit an affected JSON record when its introduction cannot be established" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    allow(matcher).to receive(:first_introduced_version).and_return(:history_unavailable)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    expect(JSON.parse(capture_stdout { cmd_for("requests", "--json").run })).to eq []
  end

  it "preserves the reviewed introduction of an existing affected record" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).not_to receive(:first_introduced_version)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "2.29.0" }] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => { "source" => "matched", "upstream_evidence" => reviewed_git_evidence },
      }))

      cmd_for("requests", "--output", dir, "--new-history").run

      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "2.29.0" }])
    end
  end

  it "summarises unavailable history deterministically by formula" do
    Dir.mktmpdir do |dir|
      emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(dir, verbose: false, close_open_ranges: false)
      emitter.record_history_unavailable("requests")
      emitter.record_history_unavailable("curl")
      emitter.record_history_unavailable("requests")

      expect { emitter.finish }
        .to output(/3 history-unavailable skips.*Unavailable history by formula:\n    curl: 1\n    requests: 2/m)
        .to_stdout
    end
  end

  it "leaves an existing open range unchanged when formula history is unavailable" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return(:history_unavailable)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      existing = {
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "1.0" }] }],
        }],
        "database_specific" => { "source" => "matched" },
      }
      File.write(path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/formula history is unavailable; skipping automatic update/).to_stderr
      expect([JSON.parse(File.read(path)), Homebrew.failed?]).to eq [existing, false]
    end
  end

  it "rejects an unknown fixed-history result" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return(:future_result)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to raise_error(TypeError, /unexpected fixed-history result: :future_result/)
    end
  end

  it "walks history when an existing matched record has no ranges" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return("2.28.1")
    expect(matcher).to receive(:first_introduced_version).and_return("2.27.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ecosystem_specific" => { "upstream_fixed_in" => "2.28.1" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      cmd_for("requests", "--output", dir, "--new-history").run
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "2.27.0" }, { "fixed" => "2.28.1" }])
    end
  end

  it "walks history and closes an existing open range with --new-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_fixed_version).and_return("2.28.1")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "1.0" }] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.28.1" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/1 history walks/).to_stdout
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "1.0" }, { "fixed" => "2.28.1" }])
    end
  end

  it "walks history and reopens an existing terminal range with --new-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_reintroduced_version).and_return("2.31.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "range_state" => "fixed", "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/1 history walks/).to_stdout
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "0" }, { "fixed" => "2.30.0" }, { "introduced" => "2.31.0" }])
    end
  end

  it "leaves a terminal range unchanged when history cannot prove a reintroduction" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_reintroduced_version).and_return(:not_reintroduced)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      existing = {
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }
      File.write(path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/could not find a prior non-affected version/).to_stderr
      expect(JSON.parse(File.read(path))).to eq existing
      expect(Homebrew.failed?).to be true
    end
  end

  it "holds unavailable reintroduction history without failing the run" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    allow(matcher).to receive(:first_reintroduced_version).and_return(:history_unavailable)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      original = JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      })
      File.write(path, original)
      output = capture_stdout { cmd_for("requests", "--output", dir, "--new-history").run }

      expect([File.read(path), Homebrew.failed?, output.include?("1 history-unavailable skips")])
        .to eq [original, false, true]
    end
  end

  it "leaves a terminal range unchanged when the new boundary precedes the reviewed boundary" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).to receive(:first_reintroduced_version).and_return("2.29.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      existing = {
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "upstream_fixed_in" => "2.32.0" },
        }],
        "database_specific" => { "source" => "matched", "upstream_evidence" => reviewed_git_evidence },
      }
      File.write(path, JSON.generate(existing))

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/reintroduction 2\.29\.0 does not follow its reviewed range/).to_stderr
      expect(JSON.parse(File.read(path))).to eq existing
      expect(Homebrew.failed?).to be true
    end
  end

  it "fails closed when an existing record is malformed" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).not_to receive(:first_fixed_version)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, "{")

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/malformed alias/).to_stderr
      expect(File.read(path)).to eq "{"
      expect(Homebrew.failed?).to be true
    end
  end

  it "does not walk history for a new record with --no-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).not_to receive(:first_fixed_version)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      cmd_for("requests", "--output", dir, "--no-history").run
    end
  end

  it "does not close an existing open range with --no-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).not_to receive(:first_fixed_version)
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "1.0" }] }],
        }],
        "database_specific" => { "source" => "matched" },
      }))

      cmd_for("requests", "--output", dir, "--no-history").run
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "1.0" }])
    end
  end

  it "does not rewrite an existing terminal range as affected with --no-history" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      existing = {
        "id"                => "BREW-requests-CVE-2024-1234",
        "affected"          => [{
          "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"             => [{ "type" => "ECOSYSTEM", "events" => [
            { "introduced" => "0" }, { "fixed" => "2.30.0" }
          ] }],
          "ecosystem_specific" => { "range_state" => "fixed" },
        }],
        "database_specific" => { "source" => "matched" },
      }
      File.write(path, JSON.generate(existing))

      cmd_for("requests", "--output", dir, "--no-history").run

      expect(JSON.parse(File.read(path))).to eq existing
    end
  end

  it "derives the introduction for a new record that is still affected" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.32.0")
    matcher = Homebrew::Vulns::Match.new
    expect(matcher).not_to receive(:first_fixed_version)
    expect(matcher).to receive(:first_introduced_version).with(requests, anything, first_fixed: nil)
                                                         .and_return("2.30.0")
    allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

    Dir.mktmpdir do |dir|
      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/1 history walks/).to_stdout
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ranges", 0, "events"))
        .to eq([{ "introduced" => "2.30.0" }])
    end
  end

  it "drops :not_applicable hits instead of emitting them as open ranges" do
    allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[{ "id" => "CVE-2024-1234" }], []])
    allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-1234").and_return(
      { "id" => "CVE-2024-1234", "affected" => [{
        "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
        "ranges"  => [{ "type"   => "ECOSYSTEM",
                        "events" => [{ "introduced" => "3.0.0" }, { "fixed" => "3.0.4" }] }],
      }] },
    )

    expect(JSON.parse(capture_stdout { cmd_for("requests", "--json", "--no-history").run })).to eq []
  end

  context "with an ambiguous current prerelease" do
    let(:current) do
      formula("openclaw-cli") do
        T.bind(self, T.class_of(Formula))
        url "https://registry.npmjs.org/openclaw/-/openclaw-2026.2.22-2.tgz"
      end
    end
    let(:matcher) { Homebrew::Vulns::Match.new }

    before do
      allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[{ "id" => "CVE-2026-22217" }]])
      allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2026-22217").and_return({
        "id" => "CVE-2026-22217", "summary" => "Current upstream summary", "affected" => [{
          "package" => { "ecosystem" => "npm", "name" => "openclaw" },
          "ranges"  => [{ "type" => "SEMVER", "events" => [{ "introduced" => "2026.2.22" }] }],
        }]
      })
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)
    end

    it "emits the current ambiguity as a JSON review lead instead of dropping the hit" do
      expect(matcher).not_to receive(:first_fixed_version)
      expect(matcher).not_to receive(:first_introduced_version)
      records = JSON.parse(capture_stdout { cmd_for("openclaw-cli", "--json", formulae: [current]).run })

      expect([records.length, records.dig(0, "database_specific", "confidence"),
              records.dig(0, "affected", 0, "ecosystem_specific"),
              records.dig(0, "database_specific", "review_reason")])
        .to eq [1, "medium", { "fix" => nil }, "prerelease_boundary"]
    end

    it "writes an uncomparable lead for a new candidate under --new-history" do
      expect(matcher).not_to receive(:first_fixed_version)
      expect(matcher).not_to receive(:first_introduced_version)
      Dir.mktmpdir do |dir|
        cmd_for("openclaw-cli", "--output", dir, "--new-history", formulae: [current]).run
        paths = Dir.glob(File.join(dir, "*.json"))
        expect(paths.length).to eq 1
        record = JSON.parse(File.read(paths.fetch(0)))
        expect([record.dig("database_specific", "confidence"), record.dig("affected", 0, "ecosystem_specific"),
                record.dig("database_specific", "review_reason")])
          .to eq ["medium", { "fix" => nil }, "prerelease_boundary"]
      end
    end

    it "refreshes a reviewed interval after a state override resolves current ambiguity" do
      hit = matcher.advisories_for(current).fetch(0)
      record = matcher.to_brew_record(current, hit)
      record[:database_specific].delete(:review_reason)
      record[:summary] = "Before review"
      record[:affected].fetch(0)[:ranges].fetch(0)[:events] = [{ introduced: "2026.2.22-2" }]
      record[:affected].fetch(0)[:ecosystem_specific] = { range_state: "affected", fix: nil }
      expect(FormulaVersions).not_to receive(:new)
      allow(Homebrew::Vulns::Match).to receive(:new).and_call_original

      Dir.mktmpdir do |dir|
        overrides_path = File.join(dir, "overrides.yml")
        File.write(overrides_path, <<~YAML)
          openclaw-cli:
            advisories:
              CVE-2026-22217:
                range_state: affected
        YAML
        record_path = File.join(dir, "#{record.fetch(:id)}.json")
        File.write(record_path, JSON.generate(record))
        expect do
          cmd_for("openclaw-cli", "--output", dir, "--new-history", "--overrides", overrides_path,
                  formulae: [current]).run
        end.to output(/1 records written.*0 history walks/).to_stdout.and output("").to_stderr
        updated = JSON.parse(File.read(record_path))
        expect([updated["summary"], updated.dig("affected", 0, "ranges", 0, "events"),
                updated.dig("affected", 0, "ecosystem_specific", "range_state"),
                updated.dig("database_specific", "review_reason"), Homebrew.failed?])
          .to eq ["Current upstream summary", [{ "introduced" => "2026.2.22-2" }], "affected", nil, false]
      end
    end

    it "still requires reviewed ranges for a new record with an ambiguous state override" do
      expect(FormulaVersions).not_to receive(:new)
      allow(Homebrew::Vulns::Match).to receive(:new).and_call_original
      Dir.mktmpdir do |dir|
        overrides_path = File.join(dir, "overrides.yml")
        File.write(overrides_path, <<~YAML)
          openclaw-cli:
            advisories:
              CVE-2026-22217:
                range_state: affected
        YAML
        expect do
          cmd_for("openclaw-cli", "--output", dir, "--new-history", "--overrides", overrides_path,
                  formulae: [current]).run
        end.to output(/state override cannot be checked against upstream history.*Review its ranges and provenance/m)
          .to_stderr
        expect(Dir.glob(File.join(dir, "*.json"))).to be_empty
      end
    end

    def with_reviewed_prerelease_record(state)
      expect(matcher).not_to receive(:first_fixed_version)
      expect(matcher).not_to receive(:first_introduced_version)
      hit = matcher.advisories_for(current).fetch(0)
      record = matcher.to_brew_record(current, hit)
      record[:affected].fetch(0)[:ecosystem_specific] = { range_state: "affected", fix: nil }
      if state == :terminal
        record[:affected].fetch(0)[:ranges].fetch(0)[:events] << { fixed: "2026.2.23" }
        record[:affected].fetch(0)[:ecosystem_specific] = { range_state: "fixed", fix: "bump" }
      end
      original = JSON.generate(record)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{record.fetch(:id)}.json")
        File.write(path, original)
        expect { cmd_for("openclaw-cli", "--output", dir, "--new-history", formulae: [current]).run }
          .to output(/prerelease_boundary.*leaving.*unchanged/).to_stderr
        yield path, original
      end
    end

    it "leaves a reviewed open record intact when the current version becomes ambiguous" do
      with_reviewed_prerelease_record(:open) do |path, original|
        expect([File.read(path), Homebrew.failed?]).to eq [original, false]
      end
    end

    it "leaves a reviewed terminal record intact when the current version becomes ambiguous" do
      with_reviewed_prerelease_record(:terminal) do |path, original|
        expect([File.read(path), Homebrew.failed?]).to eq [original, false]
      end
    end
  end

  it "does not overwrite an existing source: generated record" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(path, JSON.generate({ "id"                => "BREW-requests-CVE-2024-1234",
                                       "database_specific" => { "source" => "generated" },
                                       "affected"          => [{
                                         "package"            => { "ecosystem" => "Homebrew", "name" => "requests" },
                                         "ecosystem_specific" => { "fix" => "patch" },
                                       }] }))

      matcher = Homebrew::Vulns::Match.new
      expect(matcher).not_to receive(:first_fixed_version)
      allow(Homebrew::Vulns::Match).to receive(:new).and_return(matcher)

      expect { cmd_for("requests", "--output", dir, "--new-history").run }
        .to output(/0 records written.*1 generated left as-is/).to_stdout
      expect(JSON.parse(File.read(path)).dig("affected", 0, "ecosystem_specific", "fix")).to eq "patch"
    end
  end

  it "emits records as JSON with --json" do
    stub_osv_hit("GHSA-old", aliases: ["CVE-2024-1234"], fixed: "2.28.1")

    records = JSON.parse(capture_stdout { cmd_for("requests", "--json", "--no-history").run })
    expect(records.length).to eq 1
    expect(records.first["id"]).to eq "BREW-requests-CVE-2024-1234"
    expect(records.first["upstream"]).to contain_exactly("CVE-2024-1234", "GHSA-old")
  end

  it "prints a per-hit summary in text mode" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    expect { cmd_for("requests", "--no-history").run }
      .to output(/requests 2\.31\.0.*CVE-2024-1234 \[git, high\].*fixed \(upstream 2\.28\.1\).*1 candidate/m)
      .to_stdout
  end

  it "loads the Repology index from --repology=<file> instead of the published feed" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "repology.json")
      File.write(path, JSON.generate({ "meta" => {}, "formulae" => {} }))
      expect(Homebrew::Vulns::Repology).not_to receive(:load)

      records = JSON.parse(capture_stdout do
        cmd_for("requests", "--json", "--no-history", "--repology", path).run
      end)
      expect(records.first["id"]).to eq "BREW-requests-CVE-2024-1234"
    end
  end

  it "loads reviewed candidate corrections from --overrides=<file>" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.31.0")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "overrides.yml")
      File.write(path, <<~YAML)
        requests:
          advisories:
            CVE-2024-1234:
              range_state: affected
              upstream_fixed_in:
      YAML

      records = JSON.parse(capture_stdout do
        cmd_for("requests", "--json", "--no-history", "--overrides", path).run
      end)
      affected = records.first.fetch("affected").first
      expect(affected.dig("ranges", 0, "events")).to eq [{ "introduced" => "0" }]
      expect(affected.fetch("ecosystem_specific")).to eq("fix" => nil, "range_state" => "affected")
    end
  end

  it "requires manual ranges for a new record when state overrides conflict with upstream history" do
    %w[affected fixed].each do |state|
      stub_osv_hit("CVE-2024-1234", fixed: (state == "affected") ? "2.28.1" : "2.32.0")
      expect(FormulaVersions).not_to receive(:new)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "overrides.yml")
        File.write(path, <<~YAML)
          requests:
            advisories:
              CVE-2024-1234:
                range_state: #{state}
        YAML

        expect do
          records = JSON.parse(capture_stdout do
            cmd_for("requests", "--json", "--overrides", path).run
          end)
          expect(records).to eq []
        end.to output(/state override disagrees with upstream history.*Review its ranges and provenance together/m)
          .to_stderr
      end
    end
  end

  it "distinguishes uncheckable evidence from a state override conflicting with upstream history" do
    allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[{ "id" => "CVE-2024-1234" }], []])
    allow(Homebrew::Vulns::OSV).to receive(:vulnerability).with("CVE-2024-1234").and_return(
      { "id" => "CVE-2024-1234", "affected" => [{
        "package" => { "ecosystem" => "GIT", "name" => "https://github.com/psf/requests" },
        "ranges"  => [{ "type"   => "GIT",
                        "events" => [{ "introduced" => "0" }, { "fixed" => "f" * 40 }] }],
      }] },
    )
    expect(FormulaVersions).not_to receive(:new)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "overrides.yml")
      File.write(path, <<~YAML)
        requests:
          advisories:
            CVE-2024-1234:
              range_state: affected
      YAML

      expect do
        records = JSON.parse(capture_stdout do
          cmd_for("requests", "--json", "--overrides", path).run
        end)
        expect(records).to eq []
      end.to output(
        /state override cannot be checked against upstream history.*Review its ranges and provenance together/m,
      ).to_stderr
    end
  end

  it "uses an affected override before transition detection in --new-history mode" do
    stub_osv_hit("CVE-2024-1234", fixed: "2.31.0")
    expect(FormulaVersions).not_to receive(:new)

    Dir.mktmpdir do |dir|
      overrides_path = File.join(dir, "overrides.yml")
      File.write(overrides_path, <<~YAML)
        requests:
          advisories:
            CVE-2024-1234:
              range_state: affected
              upstream_fixed_in:
      YAML
      record_path = File.join(dir, "BREW-requests-CVE-2024-1234.json")
      File.write(record_path, JSON.generate({
        "id"                => "BREW-requests-CVE-2024-1234",
        "upstream"          => ["CVE-2024-1234"],
        "affected"          => [{
          "package" => { "ecosystem" => "Homebrew", "name" => "requests" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }] }],
        }],
        "database_specific" => {
          "source"            => "matched",
          "upstream_evidence" => reviewed_git_evidence,
        },
      }))

      expect do
        cmd_for("requests", "--output", dir, "--new-history", "--overrides", overrides_path).run
      end.to output(/0 history walks/).to_stdout

      affected = JSON.parse(File.read(record_path)).fetch("affected").first
      expect(affected.dig("ranges", 0, "events")).to eq [{ "introduced" => "0" }]
      expect(affected.fetch("ecosystem_specific")).to eq("fix" => nil, "range_state" => "affected")
    end
  end

  it "raises on an unreadable --repology file" do
    expect { cmd_for("requests", "--json", "--repology", "/nonexistent/repology.json").run }
      .to raise_error(Errno::ENOENT)
  end

  it "reports an OSV outage and finishes the emitter without raising" do
    allow(Homebrew::Vulns::OSV).to receive(:query_batch)
      .and_raise(Homebrew::Vulns::OSV::ApiError, "503")

    expect { cmd_for("requests", "--json").run }
      .to output("[]\n").to_stdout.and output(/OSV query failed: 503/).to_stderr
    expect(Homebrew.failed?).to be true
  end

  it "iterates every core formula with --all and streams to --output" do
    requests
    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core",
                               formula_names: ["requests", "broken"])
    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(Formulary).to receive(:factory).with("requests").and_return(requests)
    allow(Formulary).to receive(:factory).with("broken").and_raise(RuntimeError, "boom")
    stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")

    Dir.mktmpdir do |dir|
      expect { described_class.new(["--all", "--output", dir, "--no-history"]).run }
        .to output(/1 records written/).to_stdout
        .and output(/Error loading formula 'broken': boom/).to_stderr
      expect(File).to exist(File.join(dir, "BREW-requests-CVE-2024-1234.json"))
    end
  end

  context "with --formula-list" do
    before do
      requests
      core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core",
                                 formula_names: ["requests", "unselected"])
      allow(CoreTap).to receive(:instance).and_return(core_tap)
      allow(Formulary).to receive(:factory).with("requests").and_return(requests)
      allow(Homebrew::Vulns::OSV).to receive(:query_batch).and_return([[], []])
    end

    def run_formula_list(contents, *extra_args, mode: "--reconcile-history")
      Dir.mktmpdir do |dir|
        list = File.join(dir, "formulae.txt")
        overrides = File.join(dir, "overrides.yml")
        File.write(list, contents)
        File.write(overrides, "{}\n")
        described_class.new(["--formula-list", list, mode, "--output", dir,
                             "--overrides", overrides, *extra_args]).run
      end
    end

    it "loads only listed core formulae once and keeps live Repology lookups disabled" do
      expect(Formulary).to receive(:factory).with("requests").once.and_return(requests)
      expect(Formulary).not_to receive(:factory).with("unselected")
      expect(Homebrew::Vulns::Repology).not_to receive(:lookup)
      run_formula_list("requests\nrequests\n")
    end

    it "leaves removed formulae unqueried" do
      expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)
      expect { run_formula_list("removed\n") }.to output(%r{removed: no longer in homebrew/core}).to_stderr
    end

    it "does not expand an empty list to the whole tap" do
      expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)
      run_formula_list("")
    end

    it "rejects named formulae alongside a list" do
      expect { run_formula_list("requests\n", "requests") }.to raise_error(UsageError, /does not take named/)
    end

    it "requires a history mode" do
      expect { described_class.new(["--formula-list", "/unused"]).run }
        .to raise_error(UsageError, /--formula-list.*--reconcile-history/)
    end

    it "rejects combining a list with --all" do
      expect { run_formula_list("requests\n", "--all") }.to raise_error(UsageError, /mutually exclusive/)
    end

    context "with --new-history" do
      it "writes only the selected formula without overrides" do
        stub_osv_hit("CVE-2024-1234", fixed: "2.28.1")
        matcher = Homebrew::Vulns::Match.new(bulk: true)
        allow(matcher).to receive_messages(first_fixed_version: "2.28.1", first_introduced_version: "2.20.0")
        expect(Homebrew::Vulns::Match).to receive(:new)
          .with(repology: nil, overrides: nil, bulk: true, strict_upstream: false).and_return(matcher)
        expect(Formulary).to receive(:factory).with("requests").once.and_return(requests)
        expect(Formulary).not_to receive(:factory).with("unselected")
        expect(Homebrew::Vulns::Repology).not_to receive(:lookup)

        Dir.mktmpdir do |dir|
          list = File.join(dir, "formulae.txt")
          File.write(list, "requests\nrequests\n")
          unselected = File.join(dir, "BREW-unselected-CVE-2024-1234.json")
          original = JSON.generate({
            "id" => "BREW-unselected-CVE-2024-1234", "upstream" => ["CVE-2024-1234"],
            "affected" => [{ "package" => { "ecosystem" => "Homebrew", "name" => "unselected" } }]
          })
          File.write(unselected, original)

          described_class.new(["--formula-list", list, "--new-history", "--output", dir]).run

          selected = JSON.parse(File.read(File.join(dir, "BREW-requests-CVE-2024-1234.json")))
          expect([selected.dig("affected", 0, "ranges", 0, "events"), File.read(unselected)])
            .to eq [[{ "introduced" => "2.20.0" }, { "fixed" => "2.28.1" }], original]
        end
      end

      it "does not expand an empty daily list to the whole tap" do
        expect(Homebrew::Vulns::OSV).not_to receive(:query_batch)
        run_formula_list("", mode: "--new-history")
      end
    end
  end

  it "counts only selected formulae in a reconciliation shard's unvisited summary" do
    Dir.mktmpdir do |dir|
      %w[requests unrelated].each do |name|
        File.write(File.join(dir, "BREW-#{name}-CVE-1.json"), JSON.generate({
          "id" => "BREW-#{name}-CVE-1", "database_specific" => { "source" => "matched" },
          "affected" => [{ "package" => { "name" => name } }]
        }))
      end
      emitter = Homebrew::DevCmd::AdvisoryMatch::DirEmitter.new(dir, verbose: false, close_open_ranges: false,
                                                reconcile_history: true, formula_names: ["requests"])
      expect { emitter.finish }.to output(/1 matched records not revisited/).to_stdout
    end
  end

  it "rejects --all with --json" do
    expect { described_class.new(["--all", "--json"]) }.to raise_error(UsageError, /mutually exclusive/)
  end

  it "requires --output with --new-history" do
    expect { described_class.new(["requests", "--new-history"]) }
      .to raise_error(UsageError, /--new-history.*--output/)
  end

  it "rejects --new-history with --no-history" do
    expect { described_class.new(["requests", "--output", "out", "--new-history", "--no-history"]) }
      .to raise_error(UsageError, /mutually exclusive/)
  end

  it "emits the formula-identity index with --index" do
    requests
    core_tap = instance_double(CoreTap, installed?: true, name: "homebrew/core", formula_names: ["requests"])
    allow(CoreTap).to receive(:instance).and_return(core_tap)
    allow(Formulary).to receive(:factory).with("requests").and_return(requests)

    output = capture_stdout { described_class.new(["--index"]).run }
    index = JSON.parse(output)
    expect(index.dig("requests", "git_repo")).to eq "https://github.com/psf/requests"
    expect(index.dig("requests", "primary_package", "ecosystem")).to eq "PyPI"
  end

  def capture_stdout
    out = StringIO.new
    old = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = old
  end
end
