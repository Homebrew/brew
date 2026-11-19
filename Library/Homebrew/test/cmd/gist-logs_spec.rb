# typed: true
# frozen_string_literal: true

require "cmd/gist-logs"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::GistLogs do
  it_behaves_like "parseable arguments"

  it "loads a Formula's build logs", :integration_test do
    setup_test_formula "testball"

    expect { brew "gist-logs", "testball", "HOMEBREW_TEST_GENERIC_OS" => "1" }
      .to output(/No logs\./).to_stderr
      .and be_a_failure
  end

  describe "--new-issue" do
    subject(:command) { described_class.new(["--new-issue", "testball"]) }

    let(:failed_formula) do
      formula("testball") do
        T.bind(self, T.class_of(Formula))
        url "testball-1.0"
      end
    end

    before do
      allow(Formulary).to receive(:resolve).and_return(failed_formula)
      allow(Homebrew::Install).to receive_messages(perform_preinstall_checks_once:   nil,
                                                   perform_build_from_source_checks: nil)
      allow(Homebrew::Diagnostic).to receive(:support_tiers).and_return([])
      allow(Homebrew::Diagnostic::Checks).to receive(:new)
        .and_return(instance_double(Homebrew::Diagnostic::Checks, build_error_checks: []))
      allow(OS).to receive(:third_party_homebrew).and_return(nil)
      stub_const("OS::ISSUES_URL", "https://docs.brew.sh/Troubleshooting")
    end

    it "declines an automatic issue for a deprecated formula before uploading logs" do
      allow(failed_formula).to receive(:deprecated?).and_return(true)
      expect { command.run }.to raise_error(SystemExit)
        .and output(/Please do not file Homebrew issues for problems specific to Tier 3/).to_stderr
    end

    it "can open an issue for a developer's stable bottle build when a HEAD keg is installed", :no_api do
      failed_formula.path.dirname.mkpath
      failed_formula.path.write <<~RUBY
        class Testball < Formula
          url "https://example.com/testball-1.0.tar.gz"
          head "https://example.com/testball.git"
        end
      RUBY
      keg = failed_formula.rack/"HEAD-abcdef"
      keg.mkpath
      tab = Tab.empty
      tab.tabfile = keg/AbstractTab::FILENAME
      tab.source["spec"] = "head"
      tab.write
      failed_formula.logs.mkpath
      failed_formula.build_options_log.write("testball --build-bottle --build-from-source HOMEBREW_DEVELOPER=1")
      ENV.delete("HOMEBREW_DEVELOPER")
      allow(Formulary).to receive(:resolve).and_call_original
      allow(SystemConfig).to receive(:dump_verbose_config)
      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read).with("#{HOMEBREW_PREFIX}/bin/brew", "doctor", err: :out).and_return("")
      allow(GitHub::API).to receive(:credentials_type).and_return(:env_token)
      allow(GitHub).to receive(:create_gist).and_return("https://example.com/gist")

      expect(GitHub).to receive(:create_issue).with(CoreTap.instance.full_name, anything, "https://example.com/gist")
      command.run
    end

    test_each(%w[--build-from-source --build-bottle --cc=clang --HEAD]) do |flag|
      it "routes a recorded #{flag} build to Discussions" do
        ENV["HOMEBREW_DEVELOPER"] = "1"
        failed_formula.logs.mkpath
        (failed_formula.logs/"00.options.out").write("testball #{flag}")
        expect { command.run }.to raise_error(SystemExit)
          .and output(/Please do not file Homebrew issues for problems specific to Tier 3/).to_stderr
      end
    end
  end

  describe ".truncate_text_to_approximate_size" do
    let(:glue) { "\n[...snip...]\n" } # hard-coded copy from truncate_text_to_approximate_size

    it "truncates long text to approximate size" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n)
      expect(s.length).to eq(n)
      expect(s).to match(/^x+#{Regexp.escape(glue)}x+$/)
    end

    it "respects front_weight: 0.0" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n, front_weight: 0.0)
      expect(s).to eq(glue + ("x" * (n - glue.length)))
    end

    it "respects front_weight: 1.0" do
      n = 20
      long_s = "x" * 40

      s = described_class.truncate_text_to_approximate_size(long_s, n, front_weight: 1.0)
      expect(s).to eq(("x" * (n - glue.length)) + glue)
    end
  end
end
