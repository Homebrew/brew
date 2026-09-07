# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/cat"

RSpec.describe Homebrew::DevCmd::Cat do
  it_behaves_like "parseable arguments"

  context "when using bat" do
    sig { returns(Homebrew::DevCmd::Cat) }
    subject(:cat) { described_class.new(["testball"]) }

    sig { returns(Pathname) }
    let(:formula_file) { Formulary.find_formula_in_tap("testball", CoreTap.instance) }

    before do
      formula_file.dirname.mkpath
      formula_file.write <<~RUBY
        class Testball < Formula
          url "https://brew.sh/testball-1.0"
        end
      RUBY
      CoreTap.instance.clear_cache

      formula = instance_double(Formula)
      allow(Homebrew::EnvConfig).to receive(:bat?).and_return(true)
      allow(Formula).to receive(:[]).with("bat").and_return(formula)
      allow(formula).to receive(:ensure_installed!).with(
        reason:           "displaying <formula>/<cask> source",
        output_to_stderr: true,
        executable:       "bat",
      ).and_return(Pathname.new("/usr/bin/bat"))
      allow(SystemCommand).to receive(:safe_system)
    end

    it "uses a system bat when configured" do
      expect(SystemCommand).to receive(:safe_system).with(Pathname.new("/usr/bin/bat"), formula_file)

      cat.run
    end

    it "preserves the native configuration path" do
      ENV["BAT_CONFIG_PATH"] = "/tmp/bat.conf"
      ENV["HOMEBREW_BAT_CONFIG_PATH"] = nil

      cat.run

      expect(ENV.fetch("BAT_CONFIG_PATH", nil)).to eq("/tmp/bat.conf")
    end

    it "deprecates the Homebrew configuration path" do
      ENV["HOMEBREW_BAT_CONFIG_PATH"] = "/tmp/legacy-bat.conf"

      expect { cat.run }.to raise_error(MethodDeprecatedError, /HOMEBREW_BAT_CONFIG_PATH.*\$BAT_CONFIG_PATH/)
    end

    it "preserves the legacy configuration override during deprecation" do
      ENV["BAT_CONFIG_PATH"] = "/tmp/bat.conf"
      ENV["HOMEBREW_BAT_CONFIG_PATH"] = "/tmp/legacy-bat.conf"
      allow(Homebrew::EnvConfig).to receive(:odeprecated)

      cat.run

      expect(ENV.fetch("BAT_CONFIG_PATH")).to eq("/tmp/legacy-bat.conf")
    end
  end

  it "prints the content of a given Formula and Cask", :cask, :integration_test do
    formula_file = setup_test_formula "testball"

    expect { brew "cat", "testball", "local-caffeine" }
      .to output(/#{Regexp.escape(formula_file.read)}.*#{Regexp.escape(cask_path("local-caffeine").read)}/m).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
