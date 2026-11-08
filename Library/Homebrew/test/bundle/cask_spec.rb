# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/cask"
require "bundle/skipper"
require "cask"
require "cask/cask_loader"

RSpec.describe Homebrew::Bundle::Cask do
  describe "dumping" do
    subject(:dumper) { described_class }

    context "when brew-cask is not installed" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      end

      specify do
        expect(dumper.cask_names).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when there is no cask" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        allow(Cask::Caskroom).to receive(:casks).and_return([])
      end

      specify do
        expect(dumper.cask_names).to be_empty
        expect(dumper.dump).to eql("")
      end

      it "doesn't want to greedily update a non-installed cask" do
        expect(dumper.cask_is_outdated_using_greedy?("foo")).to be(false)
      end
    end

    context "when casks `foo`, `bar` and `baz` are installed, with `baz` being a formula requirement" do
      let(:foo) { instance_double(Cask::Cask, to_s: "foo", full_name: "foo", desc: nil, config: nil, pinned?: false) }
      let(:baz) do
        instance_double(Cask::Cask, to_s: "baz", full_name: "baz", desc: "Software", config: nil, pinned?: true)
      end
      let(:bar) do
        instance_double(
          Cask::Cask, to_s:      "bar",
                      full_name: "bar",
                      desc:      nil,
                      pinned?:   false,
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

      it "dumps as `cask 'baz'` and `cask 'foo' cask 'bar'` plus descriptions, config values and pins" do
        expected = <<~RUBY
          cask "foo"
          cask "bar", args: { fontdir: "/Library/Fonts", language: "zh-TW" }, trusted: true
          # Software
          cask "baz", pin: true
        RUBY
        allow(Homebrew::Trust).to receive(:trusted_entries).with(:cask).and_return(["bar"])
        expect(dumper.dump(describe: true)).to eql(expected.chomp)
      end

      it "doesn't want to greedily update a non-installed cask" do
        expect(dumper.cask_is_outdated_using_greedy?("qux")).to be(false)
      end

      it "wants to greedily update foo if there is an update available" do
        allow(foo).to receive(:pinned?).and_return(false)
        expect(foo).to receive(:outdated?).with(greedy: true).and_return(true)
        expect(dumper.cask_is_outdated_using_greedy?("foo")).to be(true)
      end

      it "does not want to greedily update foo if it is pinned" do
        allow(foo).to receive(:pinned?).and_return(true)
        expect(foo).not_to receive(:outdated?)
        expect(dumper.cask_is_outdated_using_greedy?("foo")).to be(false)
      end

      it "does not want to greedily update bar if there is no update available" do
        allow(bar).to receive(:pinned?).and_return(false)
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
      context "with recursive dependencies" do
        let(:installed_cask) { instance_double(Cask::Cask, to_s: "editor", full_name: "editor", depends_on: {}) }
        let(:dependency_formula) do
          formula("backend") do
            T.bind(self, T.class_of(Formula))
            url "backend-1.0"
          end
        end
        let(:requested_cask) do
          Cask::Cask.new("editor") do
            version "1.0"
            url "https://example.com/editor.zip"
            depends_on cask: "editor-backend"
          end
        end

        before do
          described_class.reset!
          allow(Cask::CaskLoader).to receive(:load).with("editor").and_return(requested_cask)
          allow(Cask::CaskLoader).to receive(:load).with("editor-backend", config: nil).and_return(
            Cask::Cask.new("editor-backend") do
              version "1.0"
              url "https://example.com/editor-backend.zip"
              depends_on formula: "backend"
            end,
          )
          allow(Formula).to receive(:[]).with("backend").and_return(dependency_formula)
        end

        it "includes formula dependencies of nested casks" do
          expect(Formula).to receive(:[]).with("backend").once.and_return(dependency_formula)

          expect(dumper.formula_dependencies(["editor"], recursive: true)).to eq(["backend"])
        end

        [:build, :test, :optional].each do |kind|
          it "includes #{kind} dependencies of a cask's formula dependency" do
            T.bind(self, RSpec::Core::ExampleGroup)

            stub_formula_loader(formula("extra") do
              T.bind(self, T.class_of(Formula))
              url "extra-1.0"
            end)
            backend = formula("backend") do
              T.bind(self, T.class_of(Formula))
              url "backend-1.0"
              depends_on "extra" => kind
            end
            allow(Formula).to receive(:[]).with("backend").and_return(backend)

            expect(described_class.formula_dependencies(["editor"], recursive: true))
              .to contain_exactly("backend", "extra")
          end
        end

        it "uses the current definition when an installed cask has no dependencies" do
          allow(described_class).to receive(:casks).and_return([installed_cask])

          expect(dumper.formula_dependencies(["editor"], recursive: true)).to eq(["backend"])
        end

        it "still uses the installed definition for a non-recursive query" do
          allow(described_class).to receive(:casks).and_return([installed_cask])

          expect(dumper.formula_dependencies(["editor"])).to be_empty
        end

        it "raises when a requested cask cannot be loaded" do
          allow(Cask::CaskLoader).to receive(:load).with("editor").and_raise(Cask::CaskUnavailableError, "editor")

          expect { dumper.formula_dependencies(["editor"], recursive: true) }.to raise_error(Cask::CaskUnavailableError)
        end
      end

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
          foo = instance_double(Cask::Cask, to_s: "foo", full_name: "foo", depends_on: { formula: ["baz", "qux"] })
          bar = instance_double(Cask::Cask, to_s: "bar", full_name: "bar", depends_on: {})
          allow(Cask::Caskroom).to receive(:casks).and_return([foo, bar])
          allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
        end

        it "returns an array of unique formula dependencies" do
          expect(dumper.formula_dependencies(["foo", "bar"])).to eql(["baz", "qux"])
        end
      end

      context "when the cask is not installed" do
        before do
          described_class.reset!
          allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
        end

        it "loads formula dependencies from the cask definition" do
          cask = instance_double(
            Cask::Cask,
            to_s:       "tpack",
            full_name:  "tmuxpack/tpack/tpack",
            depends_on: { formula: ["tmux"] },
          )

          expect(Cask::CaskLoader).to receive(:load).with("tmuxpack/tpack/tpack").and_return(cask)

          expect(dumper.formula_dependencies(["tmuxpack/tpack/tpack"])).to eql(["tmux"])
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

        it "does not include pinned casks" do
          pinned_cask = instance_double(Cask::Cask, to_s: "google-chrome", pinned?: true)
          unpinned_cask = instance_double(Cask::Cask, to_s: "firefox", pinned?: false)
          allow(pinned_cask).to receive(:outdated?).with(greedy: false).and_return(true)
          allow(unpinned_cask).to receive(:outdated?).with(greedy: false).and_return(true)
          allow(Cask::Caskroom).to receive(:casks).and_return([pinned_cask, unpinned_cask])

          expect(described_class.outdated_casks).to eql(["firefox"])
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

      context "when a cask is requested from another tap" do
        let(:options) { { full_name: "thirdparty/tap/google-chrome" } }
        let(:installed_cask) do
          instance_double(Cask::Cask, to_s: "google-chrome", tap: CoreCaskTap.instance, pinned?: false)
        end

        before do
          allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(false)
          allow(described_class).to receive_messages(outdated_casks: [], casks: [installed_cask])
        end

        it "does not skip the installed token" do
          expect(described_class.preinstall!("google-chrome", **options)).to be(true)
        end

        it "reports that it will reinstall the cask" do
          expect(described_class.install_verb("google-chrome", options)).to eq("Reinstalling")
        end

        it "reinstalls from the requested tap" do
          expect(Homebrew::Bundle).to receive(:brew)
            .with("reinstall", "--cask", "thirdparty/tap/google-chrome", "--adopt", verbose: false).and_return(true)

          described_class.install!("google-chrome", **options)
        end

        context "when the installed cask is pinned" do
          before do
            allow(installed_cask).to receive(:pinned?).and_return(true)
            allow(Homebrew::Bundle).to receive(:brew).and_return(true)
          end

          test_each([false, true]) do |force|
            it "fails with an instruction to unpin the cask (force: #{force})" do
              expect do
                expect(described_class.install!("google-chrome", **options, force:)).to be(false)
              end.to output(/google-chrome is pinned.*brew unpin --cask google-chrome/m).to_stderr
            end
          end

          it "does not reinstall or unpin the cask" do
            allow(described_class).to receive(:onoe)

            expect(Homebrew::Bundle).not_to receive(:brew)

            described_class.install!("google-chrome", **options)
          end
        end

        it "does not report the requested cask as up to date" do
          expect(described_class.cask_installed_and_up_to_date?("thirdparty/tap/google-chrome")).to be(false)
        end

        it "checks the requested tap in Brewfile entries" do
          expect(described_class.check([
            Homebrew::Bundle::Dsl::Entry.new(:cask, "google-chrome", options),
          ])).to eq(["Cask thirdparty/tap/google-chrome needs to be installed or updated."])
        end

        it "changes taps even when upgrades are disabled" do
          expect(described_class.preinstall!("google-chrome", no_upgrade: true, **options)).to be(true)
        end

        it "refreshes the installed tap after reinstalling" do
          allow(described_class).to receive(:casks).and_call_original
          allow(Cask::Caskroom).to receive(:casks).and_return(
            [Cask::Cask.new("google-chrome", tap: CoreCaskTap.instance)],
            [Cask::Cask.new("google-chrome", tap: Tap.fetch("thirdparty/tap"))],
          )
          allow(Homebrew::Bundle).to receive(:brew).and_return(true)

          described_class.install!("google-chrome", **options)

          expect(described_class.preinstall!("google-chrome", **options)).to be(false)
        end

        ["google-chrome", "homebrew/cask/google-chrome", "homebrew/homebrew-cask/google-chrome"].each do |full_name|
          it "skips the installed cask when requested as #{full_name}" do
            T.bind(self, RSpec::Core::ExampleGroup)

            expect(described_class.preinstall!("google-chrome", full_name:)).to be(false)
          end
        end

        it "checks sanitised cask names" do
          allow(described_class).to receive(:cask_oldnames).and_return({})

          expect(described_class.check(
                   Homebrew::Bundle::Dsl.new(StringIO.new('cask "Google-Chrome"')).entries,
                 )).to be_empty
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

      context "when the pin option is true" do
        let(:chrome) { instance_double(Cask::Cask, to_s: "google-chrome", pinned?: false) }

        before do
          described_class.reset!
          allow(described_class).to receive_messages(installed_casks: ["google-chrome"],
                                                     outdated_casks:  ["google-chrome"], casks: [chrome])
        end

        it "pins an unpinned cask instead of upgrading it" do
          expect(Homebrew::Bundle).not_to \
            receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--cask", "google-chrome", verbose: false)
          expect(Homebrew::Bundle).to \
            receive(:system).with(HOMEBREW_BREW_FILE, "pin", "--cask", "google-chrome", verbose: false)
                            .and_return(true)
          expect(described_class.install_verb("google-chrome", pin: true)).to eq("Pinning")
          expect(described_class.preinstall!("google-chrome", pin: true)).to be(true)
          expect(described_class.install!("google-chrome", pin: true)).to be(true)
        end

        it "skips a cask that is already pinned" do
          allow(chrome).to receive(:pinned?).and_return(true)
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("google-chrome", pin: true)).to be(false)
        end

        it "installs and then pins a missing cask" do
          allow(described_class).to receive_messages(installed_casks: [], casks: [])
          expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "google-chrome", "--adopt",
                                                          verbose: false)
                                                    .and_return(true)
          expect(Homebrew::Bundle).to receive(:brew).with("pin", "--cask", "google-chrome", verbose: false)
                                                    .and_return(true)
          expect(described_class.preinstall!("google-chrome", pin: true)).to be(true)
          expect(described_class.install!("google-chrome", pin: true)).to be(true)
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

        it "trusts the cask before installing it" do
          allow(Homebrew::Bundle).to receive(:brew).and_return(true)
          expect(Homebrew::Trust).to receive(:trust!).with(:cask, "puma/puma/puma-cask")
          described_class.install!("puma-cask", full_name: "puma/puma/puma-cask", trusted: true)
        end

        it "does not trust an unqualified cask token" do
          allow(Homebrew::Bundle).to receive(:brew).and_return(true)
          expect(Homebrew::Trust).not_to receive(:trust!)
          described_class.install!("google-chrome", trusted: true)
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
