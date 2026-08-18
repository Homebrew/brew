# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/extract"

RSpec.describe Homebrew::DevCmd::Extract do
  it_behaves_like "parseable arguments"

  context "when extracting a formula" do
    let!(:target) do
      path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      (path/"Formula").mkpath
      target = Tap.from_path(path)
      raise "No tap found at #{path}" if target.nil?

      core_tap = CoreTap.instance
      core_tap.path.cd do
        system "git", "init"
        # Start with deprecated bottle syntax
        formula_file = Formulary.find_formula_in_tap("testball", core_tap)
        formula_file.dirname.mkpath
        formula_file.write <<~RUBY
          class Testball < Formula
            url "https://brew.sh/testball-0.1.tar.gz"

            bottle do
              cellar :any
            end

          end
        RUBY
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
        # Replace with a valid formula for the next version
        formula_file.write <<~RUBY
          class Testball < Formula
            url "https://brew.sh/testball-0.2.tar.gz"
          end
        RUBY
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.2"
      end
      { name: target.name, path: }
    end

    it "retrieves the most recent version of formula", :integration_test do
      path = target[:path]/"Formula/testball@0.2.rb"
      expect { brew "extract", "testball", target[:name] }
        .to output(/^#{path}$/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.2"
    end

    it "retrieves the specified version of formula" do
      path = target[:path]/"Formula/testball@0.1.rb"
      expect { described_class.new(["testball", target[:name], "--version=0.1"]).run }
        .to output(/^#{path}$/).to_stdout
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.1"
    end

    it "retrieves the compatible version of formula" do
      path = target[:path]/"Formula/testball@0.rb"
      expect { described_class.new(["testball", target[:name], "--version=0"]).run }
        .to output(/^#{path}$/).to_stdout
      expect(path).to exist
      expect(Formulary.factory(path).version).to eq "0.2"
    end
  end
end
