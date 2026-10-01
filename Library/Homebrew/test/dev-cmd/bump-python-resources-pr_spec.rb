# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-python-resources-pr"
require "utils/pypi"

RSpec.describe Homebrew::DevCmd::BumpPythonResourcesPr do
  it_behaves_like "parseable arguments"

  it "updates vulnerable resources, prepares a PR, and restores a dry run" do
    mktmpdir do |directory|
      formula_path = directory/"test.rb"
      old_url = "https://files.pythonhosted.org/packages/vulnerable-1.0.tar.gz"
      new_url = "https://files.pythonhosted.org/packages/vulnerable-1.1.tar.gz"
      original_contents = <<~RUBY
        class Test < Formula
          url "https://example.com/test-1.0.tar.gz"

          resource "vulnerable" do
            url "#{old_url}"
          end
        end
      RUBY
      formula_path.write(original_contents)

      formula = formula("test", path: formula_path, tap: CoreTap.instance) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/test-1.0.tar.gz"
        resource("vulnerable") { url old_url }
      end
      updated_formula = formula("test", path: formula_path, tap: CoreTap.instance) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/test-1.0.tar.gz"
        resource("vulnerable") { url new_url }
      end
      output_path = directory/"result.json"
      command = described_class.new([
        "--packages=vulnerable", "--dry-run", "--no-fork", "--output=#{output_path}", "test"
      ])

      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(command.args.named).to receive(:to_formulae).and_return([formula])
      allow(PyPI).to receive(:update_python_resources!) do
        formula_path.write(formula_path.read.sub(old_url, new_url))
      end
      allow(Formulary).to receive(:clear_cache)
      allow(Formulary).to receive(:factory).with(formula_path).and_return(updated_formula)
      allow(GitHub).to receive(:check_for_duplicate_pull_requests)
      expect(Homebrew::Bump).to receive(:create_pr) do |info, dry_run:, no_fork:|
        expect([dry_run, no_fork]).to eq([true, true])
        expect(info.pr_title).to eq("test: bump python resources")
        expect(info.pr_message).to include(old_url)
        expect(info.commits.fetch(0).sourcefile_path).to eq(formula_path)
        expect(formula_path.read).to include("revision 1", new_url)
        nil
      end

      command.run

      expect(JSON.parse(output_path.read)).to include(
        "attempted" => true,
        "updated"   => false,
        "reason"    => "Dry run",
      )
      expect(formula_path.read).to eq(original_contents)
    end
  end

  it "reports and preserves a successful non-dry-run update" do
    mktmpdir do |directory|
      formula_path = directory/"test.rb"
      old_url = "https://files.pythonhosted.org/packages/vulnerable-1.0.tar.gz"
      new_url = "https://files.pythonhosted.org/packages/vulnerable-1.1.tar.gz"
      original_contents = <<~RUBY
        class Test < Formula
          url "https://example.com/test-1.0.tar.gz"

          resource "vulnerable" do
            url "#{old_url}"
          end
        end
      RUBY
      formula_path.write(original_contents)

      formula = formula("test", path: formula_path, tap: CoreTap.instance) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/test-1.0.tar.gz"
        resource("vulnerable") { url old_url }
      end
      updated_formula = formula("test", path: formula_path, tap: CoreTap.instance) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/test-1.0.tar.gz"
        resource("vulnerable") { url new_url }
      end
      output_path = directory/"result.json"
      command = described_class.new(["--packages=vulnerable", "--no-fork", "--output=#{output_path}", "test"])

      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(command.args.named).to receive(:to_formulae).and_return([formula])
      allow(PyPI).to receive(:update_python_resources!) do
        formula_path.write(formula_path.read.sub(old_url, new_url))
      end
      allow(Formulary).to receive(:clear_cache)
      allow(Formulary).to receive(:factory).with(formula_path).and_return(updated_formula)
      allow(GitHub).to receive(:check_for_duplicate_pull_requests)
      allow(Homebrew::Bump).to receive(:create_pr)
        .with(instance_of(Homebrew::Bump::BumpInfo), no_fork: true, dry_run: false)
        .and_return("https://github.com/Homebrew/homebrew-core/pull/123")

      command.run

      expect(JSON.parse(output_path.read)).to include(
        "attempted" => true,
        "updated"   => true,
        "reason"    => "https://github.com/Homebrew/homebrew-core/pull/123",
      )
      expect(formula_path.read).to include("revision 1", new_url)
    end
  end

  it "restores the formula when resource updating raises an error" do
    mktmpdir do |directory|
      formula_path = directory/"test.rb"
      old_url = "https://files.pythonhosted.org/packages/vulnerable-1.0.tar.gz"
      original_contents = <<~RUBY
        class Test < Formula
          url "https://example.com/test-1.0.tar.gz"

          resource "vulnerable" do
            url "#{old_url}"
          end
        end
      RUBY
      formula_path.write(original_contents)

      formula = formula("test", path: formula_path, tap: CoreTap.instance) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/test-1.0.tar.gz"
        resource("vulnerable") { url old_url }
      end
      output_path = directory/"result.json"
      command = described_class.new(["--packages=vulnerable", "--output=#{output_path}", "test"])

      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(command.args.named).to receive(:to_formulae).and_return([formula])
      allow(PyPI).to receive(:update_python_resources!) do
        formula_path.write("partially updated")
        raise ArgumentError, "cannot resolve metadata"
      end
      expect(Homebrew::Bump).not_to receive(:create_pr)

      command.run

      expect(JSON.parse(output_path.read)).to include(
        "attempted" => false,
        "updated"   => false,
        "reason"    => "`update_python_resources!` raised `ArgumentError`: cannot resolve metadata",
      )
      expect(formula_path.read).to eq(original_contents)
    end
  end
end
