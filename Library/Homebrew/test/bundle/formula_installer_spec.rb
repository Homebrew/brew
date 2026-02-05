# frozen_string_literal: true

require "bundle"
require "formula"
require "bundle/formula_installer"
require "bundle/formula_dumper"
require "bundle/brew_services"

RSpec.describe Homebrew::Bundle::FormulaInstaller do
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
          allow(Homebrew::Bundle::BrewServices).to receive(:started?).with(formula_name).and_return(true)
        end

        context "with a successful installation" do
          it "start service" do
            expect(Homebrew::Bundle::BrewServices).not_to receive(:start)
            described_class.preinstall!(formula_name, start_service: true)
            described_class.install!(formula_name, start_service: true)
          end
        end

        context "with a skipped installation" do
          it "start service" do
            expect(Homebrew::Bundle::BrewServices).not_to receive(:start)
            described_class.install!(formula_name, preinstall: false, start_service: true)
          end
        end
      end

      context "when service is not running" do
        before do
          allow(Homebrew::Bundle::BrewServices).to receive(:started?).with(formula_name).and_return(false)
        end

        context "with a successful installation" do
          it "start service" do
            expect(Homebrew::Bundle::BrewServices).to \
              receive(:start).with(formula_name, file: nil, verbose: false).and_return(true)
            described_class.preinstall!(formula_name, start_service: true)
            described_class.install!(formula_name, start_service: true)
          end
        end

        context "with a skipped installation" do
          it "start service" do
            expect(Homebrew::Bundle::BrewServices).to \
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
          expect(Homebrew::Bundle::BrewServices).to \
            receive(:restart).with(formula_name, file: nil, verbose: false).and_return(true)
          described_class.preinstall!(formula_name, restart_service: :always)
          described_class.install!(formula_name, restart_service: :always)
        end
      end

      context "with a skipped installation" do
        it "restart service" do
          expect(Homebrew::Bundle::BrewServices).to \
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
        allow(Homebrew::Bundle::FormulaDumper).to receive(:formulae_by_full_name).and_call_original
        allow(Homebrew::Bundle::FormulaDumper).to receive(:formulae_by_full_name).with("mysql").and_return(
          name:           "mysql",
          conflicts_with: ["mysql55"],
        )
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
        expect(Homebrew::Bundle::BrewServices).to receive(:stop).with("mysql55", verbose:).and_return(true)
        expect(Homebrew::Bundle::BrewServices).to receive(:stop).with("mysql56", verbose:).and_return(true)
        expect(Homebrew::Bundle::BrewServices).to receive(:restart).with(formula_name, file:    nil,
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
        expect(Homebrew::Bundle::BrewServices).to receive(:stop).with("mysql55", verbose:).and_return(true)
        expect(Homebrew::Bundle::BrewServices).to receive(:stop).with("mysql56", verbose:).and_return(true)
        expect(Homebrew::Bundle::BrewServices).to receive(:restart).with(formula_name, file:    nil,
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
      expect(Homebrew::Bundle::BrewServices).not_to receive(:restart)
      described_class.preinstall!(formula_name, restart_service: true)
    end
  end

  describe ".outdated_formulae" do
    it "calls Homebrew" do
      described_class.reset!
      expect(Homebrew::Bundle::FormulaDumper).to receive(:formulae).and_return(
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
      expect(Homebrew::Bundle::FormulaDumper).to receive(:formulae).and_return(
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
      Homebrew::Bundle::FormulaDumper.reset!
      described_class.reset!
      allow(described_class).to receive(:outdated_formulae).and_return(%w[bar])
      allow_any_instance_of(Formula).to receive(:outdated?).and_return(true)
      allow(Homebrew::Bundle::FormulaDumper).to receive(:formulae).and_return [
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
      ]
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
        allow(Homebrew::Bundle::BrewServices).to receive(:started?).with(formula_name).and_return(true)
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
        allow(Homebrew::Bundle::BrewServices).to receive(:started?).with(formula_name).and_return(false)
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
