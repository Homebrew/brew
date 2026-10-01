# typed: true
# frozen_string_literal: true

require "vulns/history"

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
end
