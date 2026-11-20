# typed: true
# frozen_string_literal: true

require "vulns/history"
require "vulns/match"

RSpec.describe Homebrew::Vulns::History do
  subject(:history) { described_class.new }

  let(:requests) do
    formula("requests") do
      T.bind(self, T.class_of(Formula))
      url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
    end
  end
  let(:other) do
    formula("other") do
      T.bind(self, T.class_of(Formula))
      url "https://example.test/other-1.0.tar.gz"
    end
  end
  let(:formula_versions) { instance_double(FormulaVersions) }

  before do
    allow(FormulaVersions).to receive(:new).and_return(formula_versions)
    allow(formula_versions).to receive(:load_error).and_return(nil)
  end

  it "returns :history_unavailable for a shallow tap" do
    allow(requests.tap!).to receive(:shallow?).and_return(true)

    expect(history.walk(requests) { :stop }).to eq :history_unavailable
  end

  it "returns :history_unavailable when the formula has no git history" do
    allow(formula_versions).to receive(:rev_list)

    expect(history.walk(requests) { :stop }).to eq :history_unavailable
  end

  it "returns :history_unavailable when a revision cannot be loaded" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_return(nil)

    expect(history.walk(requests) { nil }).to eq :history_unavailable
  end

  it "deduplicates failed loads while retaining each platform and the original error" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive_messages(formula_at_revision: nil,
                                                load_error:          NoMethodError.new("missing DSL\nsource excerpt"))
    2.times do
      [:arm, :intel].each do |arch|
        Homebrew::SimulateSystem.with(os: :linux, arch:) { history.walk(requests) { nil } }
      end
    end

    expect(history.load_failures.map do |failure|
      [failure.formula, failure.revision, failure.path, failure.platform, failure.error_class, failure.message]
    end).to eq [:arm, :intel].map { |arch|
      ["requests", "r0", "Formula/r/requests.rb", "linux/#{arch}", "NoMethodError", "missing DSL"]
    }
  end

  it "does not report a proven absent path as a failed load" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(Utils).to receive(:popen_read).and_return("Formula/r/requests.rb\n")
    allow(formula_versions).to receive_messages(formula_at_revision: nil, path_absent_at_revision?: true)
    history.walk(requests, complete: true) { nil }

    expect(history.load_failures).to be_empty
  end

  it "reports failed Git absence checks as load failures" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(Utils).to receive(:popen_read).and_return("Formula/r/requests.rb\n")
    allow(formula_versions).to receive(:formula_at_revision).and_return(nil)
    allow(formula_versions).to receive(:path_absent_at_revision?)
      .and_raise(ErrorDuringExecution.new(["git"], status: 128))
    result = history.walk(requests, complete: true) { nil }

    expect([result, history.load_failures.map(&:error_class)])
      .to eq [:history_unavailable, ["ErrorDuringExecution"]]
  end

  it "stops at the first result the block returns" do
    allow(formula_versions).to receive(:rev_list)
      .and_yield("r0", "Formula/r/requests.rb")
      .and_yield("r1", "Formula/r/requests.rb")
      .and_yield("r2", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    visited = T.let(0, Integer)

    result = history.walk(requests) do |_old|
      visited += 1
      "2.31.0" if visited == 2
    end

    expect([result, visited]).to eq ["2.31.0", 2]
  end

  it "returns nil after visiting every revision" do
    allow(formula_versions).to receive(:rev_list)
      .and_yield("r0", "Formula/r/requests.rb")
      .and_yield("r1", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)

    expect(history.walk(requests) { nil }).to be_nil
  end

  it "reuses the rev-list for later walks of the same formula" do
    expect(formula_versions).to receive(:rev_list).once.and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)

    2.times { history.walk(requests) { nil } }
  end

  it "shares revision enumeration across platform views" do
    expect(formula_versions).to receive(:rev_list).once.and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)

    [[:sequoia, :arm], [:sequoia, :intel], [:linux, :arm], [:linux, :intel]].each do |os, arch|
      Homebrew::SimulateSystem.with(os:, arch:) { history.walk(requests) { nil } }
    end
  end

  it "shares successful completeness checks across platform views" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    expect(Utils).to receive(:popen_read).once.with(
      "git", "-C", requests.tap!.path.to_s, "diff-tree", "--root", "--no-commit-id",
      "--name-only", "--find-renames", "--diff-filter=AR", "-r", "r0", safe: true
    ).and_return("Formula/r/requests.rb\n")

    [[:sequoia, :arm], [:sequoia, :intel], [:linux, :arm], [:linux, :intel]].each do |os, arch|
      Homebrew::SimulateSystem.with(os:, arch:) { history.walk(requests, complete: true) { nil } }
    end
  end

  it "keeps cached incomplete history unavailable on another platform" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    expect(Utils).to receive(:popen_read).once.with(
      "git", "-C", requests.tap!.path.to_s, "diff-tree", "--root", "--no-commit-id",
      "--name-only", "--find-renames", "--diff-filter=AR", "-r", "r0", safe: true
    ).and_return("")
    results = [:arm, :intel].map do |arch|
      Homebrew::SimulateSystem.with(os: :linux, arch:) { history.walk(requests, complete: true) { :stop } }
    end

    expect(results).to eq [:history_unavailable, :history_unavailable]
  end

  it "checks a full tap only once across formulae" do
    allow(other).to receive(:tap).and_return(requests.tap!)
    expect(requests.tap!).to receive(:shallow?).once.and_return(false)
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)

    [requests, other].each { |formula| history.walk(formula) { nil } }
  end

  it "keeps a cached shallow tap unavailable" do
    expect(requests.tap!).to receive(:shallow?).once.and_return(true)
    results = Array.new(2) { history.walk(requests) { :stop } }

    expect(results).to eq [:history_unavailable, :history_unavailable]
  end

  it "does not share shallow status between taps" do
    allow(requests.tap!).to receive(:shallow?).and_return(false)
    allow(other).to receive(:tap).and_return(instance_double(Tap, path: Pathname("/other-tap"), shallow?: true))
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    history.walk(requests) { nil }

    expect(history.walk(other) { :stop }).to eq :history_unavailable
  end

  it "rechecks shallow status in a new history instance" do
    allow(requests.tap!).to receive(:shallow?).and_return(false, true)
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    history.walk(requests) { nil }

    expect(described_class.new.walk(requests) { :stop }).to eq :history_unavailable
  end

  it "keeps revision lists separate for formulae in the same tap" do
    other_versions = instance_double(FormulaVersions)
    allow(FormulaVersions).to receive(:new).with(other, simulated_target: true).and_return(other_versions)
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    expect(other_versions).to receive(:rev_list).once.and_yield("r1", "Formula/o/other.rb")
    allow(other_versions).to receive(:formula_at_revision).and_yield(other)

    [requests, other].each { |formula| history.walk(formula) { nil } }
  end

  it "rejects history without an addition or rename into the formula name" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    allow(Utils).to receive(:popen_read).with(
      "git", "-C", requests.tap!.path.to_s, "diff-tree", "--root", "--no-commit-id",
      "--name-only", "--find-renames", "--diff-filter=AR", "-r", "r0", safe: true
    ).and_return("")

    expect(history.walk(requests, complete: true) { nil }).to eq :history_unavailable
  end

  it "accepts complete history ending at the formula's creation" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    allow(Utils).to receive(:popen_read).with(
      "git", "-C", requests.tap!.path.to_s, "diff-tree", "--root", "--no-commit-id",
      "--name-only", "--find-renames", "--diff-filter=AR", "-r", "r0", safe: true
    ).and_return("Formula/r/requests.rb\n")

    expect(history.walk(requests, complete: true) { nil }).to be_nil
  end

  it "does not reuse historical formula loads across platforms" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    expect(FormulaVersions).to receive(:new).with(requests, simulated_target: true).twice.and_return(formula_versions)

    Homebrew::SimulateSystem.with(os: :linux, arch: :arm) { history.walk(requests) { nil } }
    Homebrew::SimulateSystem.with(os: :linux, arch: :intel) { history.walk(requests) { nil } }
  end

  it "leaves history unavailable when Git cannot verify the formula's creation" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(Utils).to receive(:popen_read).and_raise(ErrorDuringExecution.new(["git"], status: 128))

    expect(history.walk(requests, complete: true) { nil }).to eq :history_unavailable
  end

  it "does not reuse a partial revision list for a complete walk" do
    allow(formula_versions).to receive(:formula_at_revision).and_yield(requests)
    allow(Utils).to receive(:popen_read).and_return("Formula/r/requests.rb\n")
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    history.walk(requests) { nil }
    expect(formula_versions).to receive(:rev_list).with("HEAD", all_history: true)
                                                  .and_yield("r0", "Formula/r/requests.rb")

    history.walk(requests, complete: true) { nil }
  end

  it "starts the named lifetime at a rename without walking the old formula name" do
    allow(FormulaVersions).to receive(:new).and_call_original

    Dir.mktmpdir do |dir|
      repository = Pathname(dir)
      old_path = repository/"Formula/o/old-requests.rb"
      path = repository/"Formula/r/requests.rb"
      old_path.dirname.mkpath
      path.dirname.mkpath
      allow(requests).to receive(:tap_path).and_return(path)
      allow(requests.tap!).to receive(:path).and_return(repository)
      git = ["git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.test",
             "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null"]
      Utils.safe_popen_read(*git, "init", "--quiet")
      old_path.write(<<~RUBY)
        class OldRequests < Formula
          desc "A historical formula with an earlier name"
          homepage "https://example.test/requests"
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.27.0.tar.gz"
          license "MIT"

          def install
            prefix.install "README"
          end
        end
      RUBY
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Add old formula")
      path.write(old_path.read.sub("OldRequests", "Requests").sub("2.27.0", "2.28.0"))
      old_path.unlink
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Rename formula")
      rename = Utils.safe_popen_read(*git, "diff-tree", "--no-commit-id", "--name-status",
                                     "--find-renames", "-r", "HEAD")
      path.atomic_write(path.read.sub("2.28.0", "2.31.0"))
      Utils.safe_popen_read(*git, "commit", "--quiet", "-am", "Update formula")
      visited = []

      result = history.walk(requests, complete: true) do |old|
        visited << old.pkg_version.to_s
        nil
      end

      expect(rename).to match(%r{\AR\d+\tFormula/o/old-requests.rb\tFormula/r/requests.rb})
      expect([result, visited]).to eq [nil, ["2.31.0", "2.28.0"]]
    end
  end

  it "walks both lifetimes across deletion and re-addition" do
    allow(FormulaVersions).to receive(:new).and_call_original

    Dir.mktmpdir do |dir|
      repository = Pathname(dir)
      path = repository/"Formula/r/requests.rb"
      path.dirname.mkpath
      allow(requests).to receive(:tap_path).and_return(path)
      allow(requests.tap!).to receive(:path).and_return(repository)
      git = ["git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.test",
             "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null"]
      Utils.safe_popen_read(*git, "init", "--quiet")
      path.write(<<~RUBY)
        class Requests < Formula
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.27.0.tar.gz"
        end
      RUBY
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Add formula")
      path.unlink
      Utils.safe_popen_read(*git, "commit", "--quiet", "-am", "Remove formula")
      path.write(<<~RUBY)
        class Requests < Formula
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-2.31.0.tar.gz"
        end
      RUBY
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Restore formula")
      visited = []

      result = history.walk(requests, complete: true) do |old|
        visited << old.pkg_version.to_s
        nil
      end

      expect([result, visited]).to eq [nil, ["2.31.0", "2.27.0"]]
    end
  end

  it "does not skip an unreadable build whose path exists" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(Utils).to receive(:popen_read).and_return("Formula/r/requests.rb\n")
    allow(formula_versions).to receive_messages(formula_at_revision: nil, path_absent_at_revision?: false)

    expect(history.walk(requests, complete: true) { nil }).to eq :history_unavailable
  end

  it "does not treat a failed tree lookup as an absent path" do
    allow(formula_versions).to receive(:rev_list).and_yield("r0", "Formula/r/requests.rb")
    allow(Utils).to receive(:popen_read).and_return("Formula/r/requests.rb\n")
    allow(formula_versions).to receive(:formula_at_revision).and_return(nil)
    allow(formula_versions).to receive(:path_absent_at_revision?)
      .and_raise(ErrorDuringExecution.new(["git"], status: 128))

    expect(history.walk(requests, complete: true) { nil }).to eq :history_unavailable
  end

  it "leaves history unavailable when Git cannot enumerate the complete revision list" do
    allow(FormulaVersions).to receive(:new).and_call_original

    Dir.mktmpdir do |dir|
      repository = Pathname(dir)
      allow(requests).to receive(:tap_path).and_return(repository/"Formula/requests.rb")
      allow(requests.tap!).to receive_messages(path: repository, shallow?: false)
      Utils.safe_popen_read("git", "-C", dir, "init", "--quiet")

      expect(history.walk(requests, complete: true) { nil }).to eq :history_unavailable
    end
  end

  context "with platform reuse" do
    let(:source_path) { "Formula/r/requests.rb" }
    let(:current_source) do
      <<~RUBY
        class Requests < Formula
          url "https://files.pythonhosted.org/packages/aa/bb/cc/requests-3.0.tar.gz"
        end
      RUBY
    end
    let(:old_source) { current_source.sub("requests-3.0", "requests-1.0") }
    let(:platforms) { [[:tahoe, :arm], [:tahoe, :intel], [:linux, :arm], [:linux, :intel]] }

    before do
      allow(FormulaVersions).to receive(:new).and_call_original
      allow_any_instance_of(FormulaVersions).to receive(:rev_list)
        .and_yield("new", source_path)
        .and_yield("old", source_path)
      allow(Utils).to receive(:popen_read).and_call_original
      ["new", "old"].zip([current_source, old_source]).each do |revision, source|
        allow(Utils).to receive(:popen_read).with("git", "cat-file", "blob", "#{revision}:#{source_path}")
                                            .and_return(source)
        allow(Utils).to receive(:popen_read)
          .with("git", "-C", requests.tap!.path.to_s, "cat-file", "blob", "#{revision}:#{source_path}", safe: true)
          .and_return(source)
      end
      allow(Utils).to receive(:popen_read)
        .with("git", "-C", requests.tap!.path.to_s, "diff-tree", "--root", "--no-commit-id", "--name-only",
              "--find-renames", "--diff-filter=AR", "-r", "old", safe: true).and_return("#{source_path}\n")
    end

    def walk_platforms(reuse:)
      walker = described_class.new
      platforms.map do |os, arch|
        versions = []
        status = Homebrew::SimulateSystem.with(os:, arch:) do
          walker.walk(requests, complete: true, reuse_platforms: reuse) do |old|
            versions << [old.pkg_version.to_s, old.resources.map(&:name)]
            nil
          end
        end
        [status, versions]
      end
    end

    def reconciled_platforms(reuse:)
      matcher = Homebrew::Vulns::Match.new
      current = Formulary.from_contents("requests", requests.tap_path, current_source)
      vulnerability = Homebrew::Vulns::Vulnerability.new({
        "id" => "CVE-2024-1234", "affected" => [{
          "package" => { "ecosystem" => "PyPI", "name" => "certifi" },
          "ranges"  => [{ "type" => "ECOSYSTEM", "events" => [{ "introduced" => "0" }, { "fixed" => "2.0" }] }],
        }]
      })
      evidence = Homebrew::Vulns::Match::Evidence.new(
        strategy: :registry, ecosystem: "PyPI", name: "certifi", resource: "certifi",
        subject_version: "1.0", key: "pkg:pypi/certifi@1.0"
      )
      hit = Homebrew::Vulns::Match::Hit.new(vulnerability:, evidence: [evidence])
      results = platforms.map do |os, arch|
        Homebrew::SimulateSystem.with(os:, arch:) do
          matcher.reconcile_history(current, hit, reuse_platforms: reuse)
        end
      end
      combined = Homebrew::Vulns::Match::ReconciledHistory.combine(results)
      [combined.state, combined.events, combined.reasons]
    end

    it "reuses independent revisions with identical observations and fewer formula loads" do
      loads = 0
      allow(Formulary).to receive(:from_contents).and_wrap_original do |original, *args, **kwargs|
        loads += 1
        original.call(*args, **kwargs)
      end
      full = walk_platforms(reuse: false)
      full_loads = loads
      loads = 0
      reused = walk_platforms(reuse: true)

      expect([reused, full_loads, loads]).to eq [full, 8, 2]
    end

    context "when a removed resource was Linux-only" do
      let(:old_source) do
        current_source.sub("requests-3.0", "requests-1.0").sub("\nend", <<~RUBY)

            on_linux do
              resource "certifi" do
                url "https://files.pythonhosted.org/packages/aa/bb/cc/certifi-1.0.tar.gz"
              end
            end
          end
        RUBY
      end

      it "preserves the removed Linux resource's affected interval with reuse on and off" do
        full = reconciled_platforms(reuse: false)
        expect(Formulary).to receive(:from_contents).exactly(6).times.and_call_original
        reused = reconciled_platforms(reuse: true)

        expect([full, reused]).to eq Array.new(2) {
          [:range, [{ introduced: "1.0" }, { fixed: "3.0" }], []]
        }
      end

      it "reloads the dependent old revision without rereading its source" do
        expect(Utils).not_to receive(:popen_read).with("git", "cat-file", "blob", anything)
        expect(Formulary).to receive(:from_contents).exactly(5).times.and_call_original
        expect(walk_platforms(reuse: true)).to eq [
          [nil, [["3.0", []], ["1.0", []]]], [nil, [["3.0", []], ["1.0", []]]],
          [nil, [["3.0", []], ["1.0", ["certifi"]]]], [nil, [["3.0", []], ["1.0", ["certifi"]]]]
        ]
      end
    end

    context "when a removed resource was macOS-only" do
      let(:old_source) do
        current_source.sub("requests-3.0", "requests-1.0").sub("\nend", <<~RUBY)

            on_macos do
              resource "certifi" do
                url "https://files.pythonhosted.org/packages/aa/bb/cc/certifi-1.0.tar.gz"
              end
            end
          end
        RUBY
      end

      it "preserves the removed macOS resource's affected interval with reuse on and off" do
        full = reconciled_platforms(reuse: false)
        expect(Formulary).to receive(:from_contents).exactly(6).times.and_call_original
        reused = reconciled_platforms(reuse: true)

        expect([full, reused]).to eq Array.new(2) {
          [:range, [{ introduced: "1.0" }, { fixed: "3.0" }], []]
        }
      end

      it "retains the old macOS resource while reusing only the independent revision" do
        expect(Formulary).to receive(:from_contents).exactly(5).times.and_call_original
        expect(walk_platforms(reuse: true)).to eq [
          [nil, [["3.0", []], ["1.0", ["certifi"]]]], [nil, [["3.0", []], ["1.0", ["certifi"]]]],
          [nil, [["3.0", []], ["1.0", []]]], [nil, [["3.0", []], ["1.0", []]]]
        ]
      end
    end

    context "when every revision has literal metadata" do
      let(:old_source) do
        current_source.sub("requests-3.0", "requests-1.0").sub("\nend", <<~RUBY)

            resource "certifi" do
              url "https://files.pythonhosted.org/packages/aa/bb/cc/certifi-1.0.tar.gz"
            end
          end
        RUBY
      end

      it "loads the classified source without reading the same Git blob again" do
        expect(Utils).not_to receive(:popen_read).with("git", "cat-file", "blob", anything)

        expect(walk_platforms(reuse: true)).to eq Array.new(4) {
          [nil, [["3.0", []], ["1.0", ["certifi"]]]]
        }
      end

      it "does not transfer the independence proof to an equal formula object" do
        proof = []
        history.walk(requests, reuse_platforms: true) do |old|
          proof = [history.platform_independent?(old), history.platform_independent?(old.dup)]
          :stop
        end

        expect(proof).to eq [true, false]
      end

      it "preserves the complete reconciled interval while loading each revision once" do
        observations = 0
        allow_any_instance_of(Homebrew::Vulns::Match).to receive(:reconciliation_observation)
          .and_wrap_original do |original, *args|
            observations += 1
            original.call(*args)
          end
        full = reconciled_platforms(reuse: false)
        full_observations = observations
        observations = 0
        expect(Formulary).to receive(:from_contents).exactly(3).times.and_call_original
        reused = reconciled_platforms(reuse: true)

        interval = [:range, [{ introduced: "1.0" }, { fixed: "3.0" }], []]
        expect([full, reused, full_observations, observations]).to eq [interval, interval, 12, 6]
      end
    end
  end
end
