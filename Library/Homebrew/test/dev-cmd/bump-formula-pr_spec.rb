# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-formula-pr"
require "utils/pypi"

RSpec.describe Homebrew::DevCmd::BumpFormulaPr do
  subject(:bump_formula_pr) { described_class.new(["test"]) }

  let(:f) do
    formula("test") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/test-1.2.3.tgz"
    end
  end

  it_behaves_like "parseable arguments"

  describe "#run" do
    it "adds updated mirrors as string literals" do
      formula_path = CoreTap.instance.new_formula_path("couchdb")
      formula_path.dirname.mkpath
      formula_path.write <<~RUBY
        class Couchdb < Formula
          url "https://www.apache.org/dyn/closer.lua?path=couchdb/source/3.5.1/apache-couchdb-3.5.1.tar.gz"
          mirror "https://archive.apache.org/dist/couchdb/source/3.5.1/apache-couchdb-3.5.1.tar.gz"
          sha256 "#{"a" * 64}"
        end
      RUBY
      CoreTap.instance.clear_cache
      Formulary.clear_cache
      Formula.clear_cache
      formula = Formulary.from_contents("couchdb", formula_path, formula_path.read)

      resource_path = mktmpdir/"apache-couchdb-3.5.2.tar.gz"
      resource_path.write("couchdb")
      updated_mirror = "https://archive.apache.org/dist/couchdb/source/3.5.2/apache-couchdb-3.5.2.tar.gz"
      command = described_class.new(["--write-only", "--no-audit", "--version=3.5.2", "couchdb"])

      allow(Homebrew).to receive(:install_bundler_gems!)
      allow(CoreTap.instance).to receive_messages(allow_bump?: true, git?: true,
                                                  remote_repository: "Homebrew/homebrew-core")
      allow(command).to receive(:check_new_version)
      allow(command).to receive(:fetch_resource_and_forced_version).and_return([resource_path, false])
      allow(command).to receive_messages(run_audit: false, update_matching_version_resources!: {})
      allow(PyPI).to receive(:update_python_resources!)
      allow(Utils::Tar).to receive(:validate_file).with(resource_path)
      allow(command.args.named).to receive(:to_formulae).and_return([formula])
      allow(Formula).to receive(:[]).with("couchdb").and_return(formula)
      expect_any_instance_of(Utils::AST::FormulaAST)
        .to receive(:add_stable_stanzas_after) do |formula_ast, name, stanzas|
        expect(name).to eq(:url)
        expect(stanzas).to include([:mirror, "mirror #{updated_mirror.inspect}"])
        formula_ast.add_stanzas_after(name, stanzas, parent: formula_ast.stanza(:stable, type: :block_call))
      end

      command.run

      expect(formula_path.read).to include "  mirror #{updated_mirror.inspect}\n  " \
                                           "sha256 #{resource_path.sha256.inspect}\n"
    end
  end

  describe "::check_throttle" do
    let(:tap) { Tap.fetch("test", "tap") }

    let(:f_throttle) do
      formula("throttle-test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/test-1.2.3.tgz"

        livecheck do
          throttle 5
        end
      end
    end

    let(:f_throttle_days) do
      formula("throttle-days-test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/test-1.2.3.tgz"

        livecheck do
          throttle days: 1
        end
      end
    end

    let(:f_throttle_rate_and_days) do
      formula("throttle-rate-and-days-test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/test-1.2.3.tgz"

        livecheck do
          throttle 5, days: 1
        end
      end
    end

    let(:throttle_error) { "Error: throttle-test should only be updated every 5 releases on multiples of 5\n" }
    let(:throttle_days_error) { "Error: throttle-days-test should only be updated every 1 day\n" }
    let(:throttle_rate_days_error) do
      "Error: throttle-rate-and-days-test should only be updated every 5 releases on multiples of 5 or 1 day\n"
    end

    context "when formula is not in a tap" do
      it "outputs nothing" do
        allow(f).to receive(:tap).and_return(nil)

        expect { bump_formula_pr.send(:check_throttle, f, "1.2.4") }.not_to output.to_stderr
      end
    end

    context "when a livecheck throttle value isn't present" do
      it "does not throttle" do
        allow(f).to receive(:tap).and_return(tap)

        expect { bump_formula_pr.send(:check_throttle, f, "1.2.4") }.not_to output.to_stderr
      end
    end

    context "when patch version is a multiple of throttle rate" do
      it "does not throttle" do
        allow(f_throttle).to receive(:tap).and_return(tap)

        expect { bump_formula_pr.send(:check_throttle, f_throttle, "1.2.5") }.not_to output.to_stderr
      end
    end

    context "when patch version is not a multiple of throttle rate" do
      it "throttles version" do
        allow(f_throttle).to receive(:tap).and_return(tap)

        expect do
          bump_formula_pr.send(:check_throttle, f_throttle, "1.2.4")
        rescue SystemExit
          nil
        end.to output(throttle_error).to_stderr
      end
    end

    context "when patch version is not a multiple and throttle days are set" do
      before do
        allow(f_throttle_rate_and_days).to receive(:tap).and_return(tap)
      end

      it "throttles version when throttle interval has not elapsed" do
        allow(Homebrew::Livecheck).to receive(:throttle_interval_elapsed?).and_return(false)

        expect do
          bump_formula_pr.send(:check_throttle, f_throttle_rate_and_days, "1.2.4")
        rescue SystemExit
          nil
        end.to output(throttle_rate_days_error).to_stderr
      end

      it "does not throttle when throttle interval has elapsed" do
        allow(Homebrew::Livecheck).to receive(:throttle_interval_elapsed?).and_return(true)

        expect { bump_formula_pr.send(:check_throttle, f_throttle_rate_and_days, "1.2.4") }.not_to output.to_stderr
      end
    end

    context "when only throttle days is set" do
      before do
        allow(f_throttle_days).to receive(:tap).and_return(tap)
      end

      it "throttles version when throttle interval has not elapsed" do
        allow(Homebrew::Livecheck).to receive(:throttle_interval_elapsed?).and_return(false)

        expect do
          bump_formula_pr.send(:check_throttle, f_throttle_days, "1.2.4")
        rescue SystemExit
          next
        end.to output(throttle_days_error).to_stderr
      end

      it "does not throttle when throttle interval has elapsed" do
        allow(Homebrew::Livecheck).to receive(:throttle_interval_elapsed?).and_return(true)

        expect do
          bump_formula_pr.send(:check_throttle, f_throttle_days, "1.2.4")
        end.not_to output.to_stderr
      end
    end
  end

  describe "::update_matching_version_resources!" do
    let(:f) do
      formula("test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/test-1.2.3.tgz"

        resource "parent" do
          url "https://brew.sh/parent-1.2.3.tar.gz"
          livecheck do
            formula :parent
          end
        end

        resource "no-parent" do
          url "https://brew.sh/no-parent-1.2.3.tar.gz"
        end
      end
    end
    let(:resource) { f.resource("parent") }
    let(:version) { "1.2.4" }

    it "only updates `:parent` resource" do
      expect(bump_formula_pr).to receive(:update_resource_block!).with(f, resource, version).and_return(:success)
      expect(bump_formula_pr.send(:update_matching_version_resources!, f, version:)).to eq({ "parent" => :success })
    end

    it "does not update `:parent` resource if set in `--resource-versions`" do
      resource_versions = { "parent" => { current_version: "1.2.3", latest_version: version } }
      expect(bump_formula_pr).not_to receive(:update_resource_block!)
      expect(bump_formula_pr.send(:update_matching_version_resources!, f, version:, resource_versions:)).to eq({})
    end
  end

  describe "::update_resources!" do
    let(:f) do
      formula("test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/test-1.0.0.tgz"

        resource "foo" do
          url "https://brew.sh/foo-1.2.3.tar.gz"
        end
      end
    end
    let(:r) { f.resource("foo") }

    it "updates to requested version" do
      version = "2.1.0"
      resource_versions = { "foo" => { current_version: "1.2.3", latest_version: version } }
      expect(bump_formula_pr).to receive(:update_resource_block!).with(f, r, version).and_return(:success)
      expect(bump_formula_pr.send(:update_resources!, f, resource_versions:)).to eq({ "foo" => :success })
    end

    it "downgrades to requested version" do
      version = "0.1.2"
      resource_versions = { "foo" => { current_version: "1.2.3", latest_version: version } }
      expect(bump_formula_pr).to receive(:update_resource_block!).with(f, r, version).and_return(:success)
      expect(bump_formula_pr.send(:update_resources!, f, resource_versions:)).to eq({ "foo" => :downgraded })
    end

    it "returns update failures" do
      version = "0.1.2"
      resource_versions = { "foo" => { current_version: "1.2.3", latest_version: version } }
      expect(bump_formula_pr).to receive(:update_resource_block!).with(f, r, version).and_return(:url_unchanged)
      expect(bump_formula_pr.send(:update_resources!, f, resource_versions:)).to eq({ "foo" => :url_unchanged })
    end
  end
end
