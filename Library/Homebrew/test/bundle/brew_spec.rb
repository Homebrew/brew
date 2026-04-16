# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/brew"
require "bundle/brew_services"
require "tsort"
require "formula"
require "tab"
require "utils/bottles"

RSpec.describe Homebrew::Bundle::Brew do
  describe "dumping" do
    subject(:dumper) { described_class }

    let(:foo) do
      instance_double(Formula,
                      name:                   "foo",
                      desc:                   "foobar",
                      oldnames:               ["oldfoo"],
                      full_name:              "qux/quuz/foo",
                      any_version_installed?: true,
                      aliases:                ["foobar"],
                      runtime_dependencies:   [],
                      deps:                   [],
                      conflicts:              [],
                      any_installed_prefix:   nil,
                      linked?:                false,
                      keg_only?:              true,
                      pinned?:                false,
                      outdated?:              false,
                      stable:                 instance_double(SoftwareSpec, bottle_defined?: false, bottled?: false),
                      tap:                    instance_double(Tap, official?: false))
    end
    let(:foo_hash) do
      {
        aliases:                  ["foobar"],
        any_version_installed?:   true,
        args:                     [],
        bottle:                   false,
        bottled:                  false,
        build_dependencies:       [],
        conflicts_with:           [],
        dependencies:             [],
        desc:                     "foobar",
        full_name:                "qux/quuz/foo",
        installed_as_dependency?: false,
        installed_on_request?:    false,
        link?:                    nil,
        name:                     "foo",
        oldnames:                 ["oldfoo"],
        outdated?:                false,
        pinned?:                  false,
        poured_from_bottle?:      false,
        version:                  nil,
        official_tap:             false,
      }
    end
    let(:bar) do
      linked_keg = Pathname("/usr/local").join("var").join("homebrew").join("linked").join("bar")
      instance_double(Formula,
                      name:                   "bar",
                      desc:                   "barfoo",
                      oldnames:               [],
                      full_name:              "bar",
                      any_version_installed?: true,
                      aliases:                [],
                      runtime_dependencies:   [],
                      deps:                   [],
                      conflicts:              [],
                      any_installed_prefix:   nil,
                      linked?:                true,
                      keg_only?:              false,
                      pinned?:                true,
                      outdated?:              true,
                      linked_keg:,
                      stable:                 instance_double(SoftwareSpec, bottle_defined?: true, bottled?: true),
                      tap:                    instance_double(Tap, official?: true),
                      bottle_hash:            {
                        cellar: ":any",
                        files:  {
                          big_sur: {
                            sha256: "abcdef",
                            url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
                          },
                        },
                      })
    end
    let(:bar_hash) do
      {
        aliases:                  [],
        any_version_installed?:   true,
        args:                     [],
        bottle:                   {
          cellar: ":any",
          files:  {
            big_sur: {
              sha256: "abcdef",
              url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
            },
          },
        },
        bottled:                  true,
        build_dependencies:       [],
        conflicts_with:           [],
        dependencies:             [],
        desc:                     "barfoo",
        full_name:                "bar",
        installed_as_dependency?: false,
        installed_on_request?:    false,
        link?:                    nil,
        name:                     "bar",
        oldnames:                 [],
        outdated?:                true,
        pinned?:                  true,
        poured_from_bottle?:      true,
        version:                  "1.0",
        official_tap:             true,
      }
    end
    let(:baz) do
      instance_double(Formula,
                      name:                   "baz",
                      desc:                   "",
                      oldnames:               [],
                      full_name:              "bazzles/bizzles/baz",
                      any_version_installed?: true,
                      aliases:                [],
                      runtime_dependencies:   [instance_double(Dependency, name: "bar")],
                      deps:                   [instance_double(Dependency, name: "bar", build?: true)],
                      conflicts:              [],
                      any_installed_prefix:   nil,
                      linked?:                false,
                      keg_only?:              false,
                      pinned?:                false,
                      outdated?:              false,
                      stable:                 instance_double(SoftwareSpec, bottle_defined?: false, bottled?: false),
                      tap:                    instance_double(Tap, official?: false))
    end
    let(:baz_hash) do
      {
        aliases:                  [],
        any_version_installed?:   true,
        args:                     [],
        bottle:                   false,
        bottled:                  false,
        build_dependencies:       ["bar"],
        conflicts_with:           [],
        dependencies:             ["bar"],
        desc:                     "",
        full_name:                "bazzles/bizzles/baz",
        installed_as_dependency?: false,
        installed_on_request?:    false,
        link?:                    false,
        name:                     "baz",
        oldnames:                 [],
        outdated?:                false,
        pinned?:                  false,
        poured_from_bottle?:      false,
        version:                  nil,
        official_tap:             false,
      }
    end

    before do
      described_class.reset!
    end

    describe "#formulae" do
      it "returns an empty array when no formulae are installed" do
        expect(dumper.formulae).to be_empty
      end
    end

    describe "#formulae_by_full_name" do
      it "returns an empty hash when no formulae are installed" do
        expect(dumper.formulae_by_full_name).to eql({})
      end

      it "returns an empty hash for an unavailable formula" do
        expect(Formula).to receive(:[]).with("bar").and_raise(FormulaUnavailableError.new("bar"))
        expect(dumper.formulae_by_full_name("bar")).to eql({})
      end

      it "exits on cyclic exceptions" do
        expect(Formula).to receive(:installed).and_return([foo, bar, baz])
        expect_any_instance_of(described_class::Topo).to receive(:tsort).and_raise(
          TSort::Cyclic,
          'topological sort failed: ["foo", "bar"]',
        )
        expect { dumper.formulae_by_full_name }.to raise_error(SystemExit)
      end

      it "returns a hash for a formula" do
        expect(Formula).to receive(:[]).with("qux/quuz/foo").and_return(foo)
        expect(dumper.formulae_by_full_name("qux/quuz/foo")).to eql(foo_hash)
      end

      it "returns an array for all formulae" do
        expect(Formula).to receive(:installed).and_return([foo, bar, baz])
        expect(bar.linked_keg).to receive(:realpath).and_return(instance_double(Pathname, basename: "1.0"))
        expect(Tab).to receive(:for_keg).with(bar.linked_keg).and_return(
          instance_double(Tab,
                          installed_as_dependency: false,
                          installed_on_request:    false,
                          poured_from_bottle:      true,
                          runtime_dependencies:    [],
                          used_options:            []),
        )
        expect(dumper.formulae_by_full_name).to eql({
          "bar"                 => bar_hash,
          "qux/quuz/foo"        => foo_hash,
          "bazzles/bizzles/baz" => baz_hash,
        })
      end
    end

    describe "#formulae_by_name" do
      it "returns a hash for a formula" do
        expect(Formula).to receive(:[]).with("foo").and_return(foo)
        expect(dumper.formulae_by_name("foo")).to eql(foo_hash)
      end
    end

    describe "#dump" do
      it "returns a dump string with installed formulae" do
        expect(Formula).to receive(:installed).and_return([foo, bar, baz])
        allow(Utils).to receive(:safe_popen_read).and_return("[]")
        expected = <<~EOS
          # barfoo
          brew "bar"
          brew "bazzles/bizzles/baz", link: false
          # foobar
          brew "qux/quuz/foo"
        EOS
        expect(dumper.dump(describe: true)).to eql(expected.chomp)
      end
    end

    describe "#formula_aliases" do
      it "returns an empty string when no formulae are installed" do
        expect(dumper.formula_aliases).to eql({})
      end

      it "returns a hash with installed formulae aliases" do
        expect(Formula).to receive(:installed).and_return([foo, bar, baz])
        expect(dumper.formula_aliases).to eql({
          "qux/quuz/foobar" => "qux/quuz/foo",
          "foobar"          => "qux/quuz/foo",
        })
      end
    end

    describe "#formula_oldnames" do
      it "returns an empty string when no formulae are installed" do
        expect(dumper.formula_oldnames).to eql({})
      end

      it "returns a hash with installed formulae old names" do
        expect(Formula).to receive(:installed).and_return([foo, bar, baz])
        expect(dumper.formula_oldnames).to eql({
          "qux/quuz/oldfoo" => "qux/quuz/foo",
          "oldfoo"          => "qux/quuz/foo",
        })
      end
    end
  end

  describe "installing" do
    let(:formula_name) { "mysql" }
    let(:options) { { args: ["with-option"] } }
    let(:installer) { described_class.new(formula_name, options) }

    before do
      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      stub_formula_loader formula(formula_name) { url "mysql-1.0" }
    end

    context "when the formula is installed" do
      before do
        allow_any_instance_of(described_class).to receive(:installed?).and_return(true)
      end

      context "with a true start_service option" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:installed?).and_return(true)
          allow(Homebrew::Bundle).to receive(:brew).with("link", formula_name, verbose: false).and_return(true)
        end

        context "when service is already running" do
          before do
            allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with(formula_name).and_return(true)
          end

          context "with a successful installation" do
            it "start service" do
              expect(Homebrew::Bundle::Brew::Services).not_to receive(:start)
              described_class.preinstall!(formula_name, start_service: true)
              described_class.install!(formula_name, start_service: true)
            end
          end

          context "with a skipped installation" do
            it "start service" do
              expect(Homebrew::Bundle::Brew::Services).not_to receive(:start)
              described_class.install!(formula_name, preinstall: false, start_service: true)
            end
          end
        end

        context "when service is not running" do
          before do
            allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with(formula_name).and_return(false)
          end

          context "with a successful installation" do
            it "start service" do
              expect(Homebrew::Bundle::Brew::Services).to \
                receive(:start).with(formula_name, file: nil, verbose: false).and_return(true)
              described_class.preinstall!(formula_name, start_service: true)
              described_class.install!(formula_name, start_service: true)
            end
          end

          context "with a skipped installation" do
            it "start service" do
              expect(Homebrew::Bundle::Brew::Services).to \
                receive(:start).with(formula_name, file: nil, verbose: false).and_return(true)
              described_class.install!(formula_name, preinstall: false, start_service: true)
            end
          end
        end
      end

      context "with an always restart_service option" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:installed?).and_return(true)
          allow(Homebrew::Bundle).to receive(:brew).with("link", formula_name, verbose: false).and_return(true)
        end

        context "with a successful installation" do
          it "restart service" do
            expect(Homebrew::Bundle::Brew::Services).to \
              receive(:restart).with(formula_name, file: nil, verbose: false).and_return(true)
            described_class.preinstall!(formula_name, restart_service: :always)
            described_class.install!(formula_name, restart_service: :always)
          end
        end

        context "with a skipped installation" do
          it "restart service" do
            expect(Homebrew::Bundle::Brew::Services).to \
              receive(:restart).with(formula_name, file: nil, verbose: false).and_return(true)
            described_class.install!(formula_name, preinstall: false, restart_service: :always)
          end
        end
      end

      context "when the link option is true" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
        end

        it "links formula" do
          allow_any_instance_of(described_class).to receive(:linked?).and_return(false)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "link", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: true)
          described_class.install!(formula_name, link: true)
        end

        it "force-links keg-only formula" do
          allow_any_instance_of(described_class).to receive(:linked?).and_return(false)
          allow_any_instance_of(described_class).to receive(:keg_only?).and_return(true)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "link", "--force", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: true)
          described_class.install!(formula_name, link: true)
        end
      end

      context "when the link option is :overwrite" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
        end

        it "overwrite links formula" do
          allow_any_instance_of(described_class).to receive(:linked?).and_return(false)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "link", "--overwrite", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: :overwrite)
          described_class.install!(formula_name, link: :overwrite)
        end
      end

      context "when the link option is false" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
        end

        it "unlinks formula" do
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: false)
          described_class.install!(formula_name, link: false)
        end
      end

      context "when the link option is nil and formula is unlinked and not keg-only" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:linked?).and_return(false)
          allow_any_instance_of(described_class).to receive(:keg_only?).and_return(false)
        end

        it "links formula" do
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "link", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: nil)
          described_class.install!(formula_name, link: nil)
        end
      end

      context "when the link option is nil and formula is linked and keg-only" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
          allow_any_instance_of(described_class).to receive(:keg_only?).and_return(true)
        end

        it "unlinks formula" do
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql",
                                                            verbose: false).and_return(true)
          described_class.preinstall!(formula_name, link: nil)

          described_class.install!(formula_name, link: nil)
        end
      end

      context "when the conflicts_with option is provided" do
        before do
          stub_formula_loader formula(formula_name) {
            url "mysql-1.0"
            conflicts_with "mysql55"
          }
          allow(described_class).to receive(:formula_installed?).and_return(true)
          allow_any_instance_of(described_class).to receive(:install_formula!).and_return(true)
          allow_any_instance_of(described_class).to receive(:upgrade_formula!).and_return(true)
        end

        it "unlinks conflicts and stops their services" do
          verbose = false
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql55",
                                                            verbose:).and_return(true)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql56",
                                                            verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:stop).with("mysql55", verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:stop).with("mysql56", verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:restart).with(formula_name, file:    nil,
                                                                                           verbose:).and_return(true)
          described_class.preinstall!(formula_name, restart_service: :always, conflicts_with: ["mysql56"])
          described_class.install!(formula_name, restart_service: :always, conflicts_with: ["mysql56"])
        end

        it "prints a message" do
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
          allow_any_instance_of(described_class).to receive(:puts)
          verbose = true
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql55",
                                                            verbose:).and_return(true)
          expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "unlink", "mysql56",
                                                            verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:stop).with("mysql55", verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:stop).with("mysql56", verbose:).and_return(true)
          expect(Homebrew::Bundle::Brew::Services).to receive(:restart).with(formula_name, file:    nil,
                                                                                           verbose:).and_return(true)
          described_class.preinstall!(formula_name, restart_service: :always, conflicts_with: ["mysql56"],
          verbose: true)
          described_class.install!(formula_name, restart_service: :always, conflicts_with: ["mysql56"],
          verbose: true)
        end
      end

      context "when the postinstall option is provided" do
        before do
          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:installed?).and_return(true)
          allow(Homebrew::Bundle).to receive(:brew).with("link", formula_name, verbose: false).and_return(true)
        end

        context "when formula has changed" do
          before do
            allow_any_instance_of(described_class).to receive(:changed?).and_return(true)
          end

          it "runs the postinstall command" do
            expect(Kernel).to receive(:system).with("custom command").and_return(true)
            described_class.preinstall!(formula_name, postinstall: "custom command")
            described_class.install!(formula_name, postinstall: "custom command")
          end

          it "reports a failure" do
            expect(Kernel).to receive(:system).with("custom command").and_return(false)
            described_class.preinstall!(formula_name, postinstall: "custom command")
            expect(described_class.install!(formula_name, postinstall: "custom command")).to be(false)
          end
        end

        context "when formula has not changed" do
          before do
            allow_any_instance_of(described_class).to receive(:changed?).and_return(false)
          end

          it "does not run the postinstall command" do
            expect(Kernel).not_to receive(:system)
            described_class.preinstall!(formula_name, postinstall: "custom command")
            described_class.install!(formula_name, postinstall: "custom command")
          end
        end
      end

      context "when the version_file option is provided" do
        before do
          Homebrew::Bundle.reset!

          allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(true)
          allow_any_instance_of(described_class).to receive(:installed?).and_return(true)
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
        end

        let(:version_file) { "version.txt" }
        let(:version) { "1.0" }

        context "when formula versions are changed and specified by the environment" do
          before do
            allow_any_instance_of(described_class).to receive(:changed?).and_return(false)
            ENV["HOMEBREW_BUNDLE_EXEC_FORMULA_VERSION_#{formula_name.upcase}"] = version
          end

          it "writes the version to the file" do
            expect(File).to receive(:write).with(version_file, "#{version}\n")
            described_class.preinstall!(formula_name, version_file:)
            described_class.install!(formula_name, version_file:)
          end
        end

        context "when using the latest formula" do
          it "writes the version to the file" do
            expect(File).to receive(:write).with(version_file, "#{version}\n")
            described_class.preinstall!(formula_name, version_file:)
            described_class.install!(formula_name, version_file:)
          end
        end
      end
    end

    context "when a formula isn't installed" do
      before do
        allow_any_instance_of(described_class).to receive(:installed?).and_return(false)
        allow_any_instance_of(described_class).to receive(:install_change_state!).and_return(false)
      end

      it "did not call restart service" do
        expect(Homebrew::Bundle::Brew::Services).not_to receive(:restart)
        described_class.preinstall!(formula_name, restart_service: true)
      end
    end

    describe ".outdated_formulae" do
      it "calls Homebrew" do
        described_class.reset!
        expect(described_class).to receive(:formulae).and_return(
          [
            { name: "a", outdated?: true },
            { name: "b", outdated?: true },
            { name: "c", outdated?: false },
          ],
        )
        expect(described_class.outdated_formulae).to eql(%w[a b])
      end
    end

    describe ".pinned_formulae" do
      it "calls Homebrew" do
        described_class.reset!
        expect(described_class).to receive(:formulae).and_return(
          [
            { name: "a", pinned?: true },
            { name: "b", pinned?: true },
            { name: "c", pinned?: false },
          ],
        )
        expect(described_class.pinned_formulae).to eql(%w[a b])
      end
    end

    describe ".formula_installed_and_up_to_date?" do
      before do
        described_class.reset!
        allow_any_instance_of(Formula).to receive(:outdated?).and_return(true)
        allow(described_class).to receive_messages(outdated_formulae: %w[bar], formulae: [
          {
            name:         "foo",
            full_name:    "homebrew/tap/foo",
            aliases:      ["foobar"],
            args:         [],
            version:      "1.0",
            dependencies: [],
            requirements: [],
          },
          {
            name:         "bar",
            full_name:    "bar",
            aliases:      [],
            args:         [],
            version:      "1.0",
            dependencies: [],
            requirements: [],
          },
        ])
        stub_formula_loader formula("foo") { url "foo-1.0" }
        stub_formula_loader formula("bar") { url "bar-1.0" }
      end

      it "returns result" do
        expect(described_class.formula_installed_and_up_to_date?("foo")).to be(true)
        expect(described_class.formula_installed_and_up_to_date?("foobar")).to be(true)
        expect(described_class.formula_installed_and_up_to_date?("bar")).to be(false)
        expect(described_class.formula_installed_and_up_to_date?("baz")).to be(false)
      end
    end

    context "when brew is installed" do
      context "when no formula is installed" do
        before do
          allow(described_class).to receive(:installed_formulae).and_return([])
          allow_any_instance_of(described_class).to receive(:conflicts_with).and_return([])
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
        end

        it "install formula" do
          expect(Homebrew::Bundle).to receive(:system)
            .with(HOMEBREW_BREW_FILE, "install", "--formula", formula_name, "--with-option", verbose: false)
            .and_return(true)
          expect(installer.preinstall!).to be(true)
          expect(installer.install!).to be(true)
        end

        it "reports a failure" do
          expect(Homebrew::Bundle).to receive(:system)
            .with(HOMEBREW_BREW_FILE, "install", "--formula", formula_name, "--with-option", verbose: false)
            .and_return(false)
          expect(installer.preinstall!).to be(true)
          expect(installer.install!).to be(false)
        end
      end

      context "when formula is installed" do
        before do
          allow(described_class).to receive(:installed_formulae).and_return([formula_name])
          allow_any_instance_of(described_class).to receive(:conflicts_with).and_return([])
          allow_any_instance_of(described_class).to receive(:linked?).and_return(true)
          allow_any_instance_of(Formula).to receive(:outdated?).and_return(true)
        end

        context "when formula upgradable" do
          before do
            allow(described_class).to receive(:outdated_formulae).and_return([formula_name])
          end

          it "upgrade formula" do
            expect(Homebrew::Bundle).to \
              receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--formula", formula_name, verbose: false)
                              .and_return(true)
            expect(installer.preinstall!).to be(true)
            expect(installer.install!).to be(true)
          end

          it "reports a failure" do
            expect(Homebrew::Bundle).to \
              receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--formula", formula_name, verbose: false)
                              .and_return(false)
            expect(installer.preinstall!).to be(true)
            expect(installer.install!).to be(false)
          end

          context "when formula pinned" do
            before do
              allow(described_class).to receive(:pinned_formulae).and_return([formula_name])
            end

            it "does not upgrade formula" do
              expect(Homebrew::Bundle).not_to \
                receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--formula", formula_name, verbose: false)
              expect(installer.preinstall!).to be(false)
            end
          end

          context "when formula not upgraded" do
            before do
              allow(described_class).to receive(:outdated_formulae).and_return([])
            end

            it "does not upgrade formula" do
              expect(Homebrew::Bundle).not_to receive(:system)
              expect(installer.preinstall!).to be(false)
            end
          end
        end
      end
    end

    describe "#changed?" do
      it "is false by default" do
        expect(described_class.new(formula_name).changed?).to be(false)
      end
    end

    describe "#start_service?" do
      it "is false by default" do
        expect(described_class.new(formula_name).start_service?).to be(false)
      end

      context "when the start_service option is true" do
        it "is true" do
          expect(described_class.new(formula_name, start_service: true).start_service?).to be(true)
        end
      end
    end

    describe "#start_service_needed?" do
      context "when a service is already started" do
        before do
          allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with(formula_name).and_return(true)
        end

        it "is false by default" do
          expect(described_class.new(formula_name).start_service_needed?).to be(false)
        end

        it "is false with {start_service: true}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, start_service: true).start_service_needed?).to be(false)
        end

        it "is false with {restart_service: true}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: true).start_service_needed?).to be(false)
        end

        it "is false with {restart_service: :changed}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :changed).start_service_needed?).to be(false)
        end

        it "is false with {restart_service: :always}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :always).start_service_needed?).to be(false)
        end
      end

      context "when a service is not started" do
        before do
          allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with(formula_name).and_return(false)
        end

        it "is false by default" do
          expect(described_class.new(formula_name).start_service_needed?).to be(false)
        end

        it "is true if {start_service: true}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, start_service: true).start_service_needed?).to be(true)
        end

        it "is true if {restart_service: true}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: true).start_service_needed?).to be(true)
        end

        it "is true if {restart_service: :changed}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :changed).start_service_needed?).to be(true)
        end

        it "is true if {restart_service: :always}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :always).start_service_needed?).to be(true)
        end
      end
    end

    describe "#restart_service?" do
      it "is false by default" do
        expect(described_class.new(formula_name).restart_service?).to be(false)
      end

      context "when the restart_service option is true" do
        it "is true" do
          expect(described_class.new(formula_name, restart_service: true).restart_service?).to be(true)
        end
      end

      context "when the restart_service option is always" do
        it "is true" do
          expect(described_class.new(formula_name, restart_service: :always).restart_service?).to be(true)
        end
      end

      context "when the restart_service option is changed" do
        it "is true" do
          expect(described_class.new(formula_name, restart_service: :changed).restart_service?).to be(true)
        end
      end
    end

    describe "#restart_service_needed?" do
      it "is false by default" do
        expect(described_class.new(formula_name).restart_service_needed?).to be(false)
      end

      context "when a service is unchanged" do
        before do
          allow_any_instance_of(described_class).to receive(:changed?).and_return(false)
        end

        it "is false with {restart_service: true}" do
          expect(described_class.new(formula_name, restart_service: true).restart_service_needed?).to be(false)
        end

        it "is true with {restart_service: :always}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :always).restart_service_needed?).to be(true)
        end

        it "is false if {restart_service: :changed}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :changed).restart_service_needed?).to be(false)
        end
      end

      context "when a service is changed" do
        before do
          allow_any_instance_of(described_class).to receive(:changed?).and_return(true)
        end

        it "is true with {restart_service: true}" do
          expect(described_class.new(formula_name, restart_service: true).restart_service_needed?).to be(true)
        end

        it "is true with {restart_service: :always}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :always).restart_service_needed?).to be(true)
        end

        it "is true if {restart_service: :changed}" do # rubocop:todo RSpec/AggregateExamples
          expect(described_class.new(formula_name, restart_service: :changed).restart_service_needed?).to be(true)
        end
      end
    end
  end
end
