# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/cask"
require "cask"

RSpec.describe Homebrew::Bundle::Cask do
  describe "dumping" do
    subject(:dumper) { described_class }

    context "when brew-cask is not installed" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      end

      it "returns empty list" do
        expect(dumper.cask_names).to be_empty
      end

      it "dumps as empty string" do # rubocop:todo RSpec/AggregateExamples
        expect(dumper.dump).to eql("")
      end
    end

    context "when there is no cask" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        allow(Cask::Caskroom).to receive(:casks).and_return([])
      end

      it "returns empty list" do
        expect(dumper.cask_names).to be_empty
      end

      it "dumps as empty string" do # rubocop:todo RSpec/AggregateExamples
        expect(dumper.dump).to eql("")
      end

      it "doesn't want to greedily update a non-installed cask" do
        expect(dumper.cask_is_outdated_using_greedy?("foo")).to be(false)
      end
    end

    context "when casks `foo`, `bar` and `baz` are installed, with `baz` being a formula requirement" do
      let(:foo) { instance_double(Cask::Cask, to_s: "foo", full_name: "foo", desc: nil, config: nil) }
      let(:baz) { instance_double(Cask::Cask, to_s: "baz", full_name: "baz", desc: "Software", config: nil) }
      let(:bar) do
        instance_double(
          Cask::Cask, to_s:      "bar",
                      full_name: "bar",
                      desc:      nil,
                      config:    instance_double(
                        Cask::Config,
                        explicit: {
                          fontdir:   "/Library/Fonts",
                          languages: ["zh-TW"],
                        },
                      )
        )
      end

      before do
        described_class.reset!

        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        allow(Cask::Caskroom).to receive(:casks).and_return([foo, bar, baz])
      end

      it "returns list %w[foo bar baz]" do
        expect(dumper.cask_names).to eql(%w[foo bar baz])
      end

      it "dumps as `cask 'baz'` and `cask 'foo' cask 'bar'` plus descriptions and config values" do
        expected = <<~EOS
          cask "foo"
          cask "bar", args: { fontdir: "/Library/Fonts", language: "zh-TW" }
          # Software
          cask "baz"
        EOS
        expect(dumper.dump(describe: true)).to eql(expected.chomp)
      end

      it "doesn't want to greedily update a non-installed cask" do
        expect(dumper.cask_is_outdated_using_greedy?("qux")).to be(false)
      end

      it "wants to greedily update foo if there is an update available" do
        expect(foo).to receive(:outdated?).with(greedy: true).and_return(true)
        expect(dumper.cask_is_outdated_using_greedy?("foo")).to be(true)
      end

      it "does not want to greedily update bar if there is no update available" do
        expect(bar).to receive(:outdated?).with(greedy: true).and_return(false)
        expect(dumper.cask_is_outdated_using_greedy?("bar")).to be(false)
      end
    end

    describe "#cask_oldnames" do
      before do
        described_class.reset!
      end

      it "returns an empty string when no casks are installed" do
        expect(dumper.cask_oldnames).to eql({})
      end

      it "returns a hash with installed casks old names" do
        foo = instance_double(Cask::Cask, to_s: "foo", old_tokens: ["oldfoo"], full_name: "qux/quuz/foo")
        bar = instance_double(Cask::Cask, to_s: "bar", old_tokens: [], full_name: "bar")
        allow(Cask::Caskroom).to receive(:casks).and_return([foo, bar])
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        expect(dumper.cask_oldnames).to eql({
          "qux/quuz/oldfoo" => "qux/quuz/foo",
          "oldfoo"          => "qux/quuz/foo",
        })
      end
    end

    describe "#formula_dependencies" do
      context "when the given casks don't have formula dependencies" do
        before do
          described_class.reset!
        end

        it "returns an empty array" do
          expect(dumper.formula_dependencies(["foo"])).to eql([])
        end
      end

      context "when multiple casks have the same dependency" do
        before do
          described_class.reset!
          foo = instance_double(Cask::Cask, to_s: "foo", depends_on: { formula: ["baz", "qux"] })
          bar = instance_double(Cask::Cask, to_s: "bar", depends_on: {})
          allow(Cask::Caskroom).to receive(:casks).and_return([foo, bar])
          allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        end

        it "returns an array of unique formula dependencies" do
          expect(dumper.formula_dependencies(["foo", "bar"])).to eql(["baz", "qux"])
        end
      end
    end
  end

  describe "installing" do
    describe ".installed_casks" do
      before do
        described_class.reset!
      end

      it "shells out" do
        expect { described_class.installed_casks }.not_to raise_error
      end
    end

    describe ".cask_installed_and_up_to_date?" do
      it "returns result" do
        described_class.reset!
        allow(described_class).to receive_messages(installed_casks: ["foo", "baz"],
                                                   outdated_casks:  ["baz"])
        expect(described_class.cask_installed_and_up_to_date?("foo")).to be(true)
        expect(described_class.cask_installed_and_up_to_date?("baz")).to be(false)
      end
    end

    context "when brew-cask is not installed" do
      describe ".outdated_casks" do
        it "returns empty array" do
          described_class.reset!
          expect(described_class.outdated_casks).to eql([])
        end
      end
    end

    context "when brew-cask is installed" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      end

      describe ".outdated_casks" do
        it "returns empty array" do
          described_class.reset!
          expect(described_class.outdated_casks).to eql([])
        end
      end

      context "when cask is installed" do
        before do
          described_class.reset!
          allow(described_class).to receive(:installed_casks).and_return(["google-chrome"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("google-chrome")).to be(false)
        end
      end

      context "when cask is outdated" do
        before do
          allow(described_class).to receive_messages(installed_casks: ["google-chrome"],
                                                     outdated_casks:  ["google-chrome"])
        end

        it "upgrades" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--cask", "google-chrome", verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("google-chrome")).to be(true)
          expect(described_class.install!("google-chrome")).to be(true)
        end
      end

      context "when cask is outdated and uses auto-update" do
        before do
          described_class.reset!
          allow(described_class).to receive_messages(cask_names: ["opera"], outdated_cask_names: [])
          allow(described_class).to receive(:cask_is_outdated_using_greedy?).with("opera").and_return(true)
        end

        it "upgrades" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--cask", "opera", verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("opera", greedy: true)).to be(true)
          expect(described_class.install!("opera", greedy: true)).to be(true)
        end
      end

      context "when cask is not installed" do
        before do
          allow(described_class).to receive(:installed_casks).and_return([])
        end

        it "installs cask" do
          expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "google-chrome", "--adopt",
                                                          verbose: false)
                                                    .and_return(true)
          expect(described_class.preinstall!("google-chrome")).to be(true)
          expect(described_class.install!("google-chrome")).to be(true)
        end

        it "installs cask with arguments" do
          expect(Homebrew::Bundle).to(
            receive(:brew).with("install", "--cask", "firefox", "--appdir=/Applications", "--adopt",
                                verbose: false)
                            .and_return(true),
          )
          expect(described_class.preinstall!("firefox", args: { appdir: "/Applications" })).to be(true)
          expect(described_class.install!("firefox", args: { appdir: "/Applications" })).to be(true)
        end

        it "reports a failure" do
          expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "google-chrome", "--adopt",
                                                          verbose: false)
                                                    .and_return(false)
          expect(described_class.preinstall!("google-chrome")).to be(true)
          expect(described_class.install!("google-chrome")).to be(false)
        end

        context "with boolean arguments" do
          it "includes a flag if true" do
            expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "iterm", "--force",
                                                            verbose: false)
                                                      .and_return(true)
            expect(described_class.preinstall!("iterm", args: { force: true })).to be(true)
            expect(described_class.install!("iterm", args: { force: true })).to be(true)
          end

          it "does not include a flag if false" do
            expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "iterm", "--adopt", verbose: false)
                                                      .and_return(true)
            expect(described_class.preinstall!("iterm", args: { force: false })).to be(true)
            expect(described_class.install!("iterm", args: { force: false })).to be(true)
          end
        end
      end

      context "when the postinstall option is provided" do
        before do
          described_class.reset!
          allow(described_class).to receive_messages(cask_names:          ["google-chrome"],
                                                     outdated_cask_names: ["google-chrome"])
          allow(Homebrew::Bundle).to receive(:brew).and_return(true)
          allow(described_class).to receive(:upgrading?).and_return(true)
        end

        it "runs the postinstall command" do
          expect(Kernel).to receive(:system).with("custom command").and_return(true)
          expect(described_class.preinstall!("google-chrome", postinstall: "custom command")).to be(true)
          expect(described_class.install!("google-chrome", postinstall: "custom command")).to be(true)
        end

        it "reports a failure when postinstall fails" do
          expect(Kernel).to receive(:system).with("custom command").and_return(false)
          expect(described_class.preinstall!("google-chrome", postinstall: "custom command")).to be(true)
          expect(described_class.install!("google-chrome", postinstall: "custom command")).to be(false)
        end
      end
    end
  end
end
