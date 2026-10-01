# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-compatibility-version"

RSpec.describe Homebrew::DevCmd::BumpCompatibilityVersion do
  it_behaves_like "parseable arguments"

  it "previews a Formula compatibility version bump", :integration_test do
    setup_test_formula "testball"

    expect { brew "bump-compatibility-version", "--dry-run", "testball" }
      .to output(/add "compatibility_version 1"/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  describe "#run" do
    before do
      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    end

    it "adds compatibility_version 1 with --write-only" do
      formula_path = mktmpdir/"foo.rb"
      formula_path.write <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0"
        end
      RUBY
      formula = formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0"
      end
      command = described_class.new(["--write-only", "foo"])
      allow(command.args.named).to receive(:to_formulae).and_return([formula])

      command.run

      expect(formula_path.read).to include "  compatibility_version 1\n"
    end

    it "increments compatibility_version with --write-only" do
      formula_path = mktmpdir/"foo.rb"
      formula_path.write <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0"
          compatibility_version 2
        end
      RUBY
      formula = formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0"
        compatibility_version 2
      end
      command = described_class.new(["--write-only", "foo"])
      allow(command.args.named).to receive(:to_formulae).and_return([formula])

      command.run

      expect(formula_path.read).to include "  compatibility_version 3\n"
    end
  end
end
