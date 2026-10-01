# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/untap"

RSpec.describe Homebrew::Cmd::Untap do
  let(:class_instance) { described_class.new(%w[arg1]) }

  it_behaves_like "parseable arguments"

  it "untaps a given Tap with an installed cask", :cask, :integration_test do
    setup_test_tap
    tap = Tap.fetch("homebrew", "foo")

    cask_source = <<~RUBY
      cask "testcask" do
        version "1.2.3"
        sha256 :no_check
        url "https://brew.sh/"
      end
    RUBY

    cask_path = tap.cask_dir/"testcask.rb"
    cask_path.dirname.mkpath
    cask_path.write(cask_source)
    tap.clear_cache

    cask = Cask::CaskLoader::FromContentLoader.new(cask_source, tap:).load(config: nil)
    InstallHelper.install_with_caskfile(cask)

    expect { brew "untap", "--force", "homebrew/foo" }
      .to output(/Untapped/).to_stderr
      .and be_a_success
  end

  it "fails without a traceback when given a formula name" do
    expect { described_class.new(["homebrew/foo/bar"]).run }
      .to output(%r{Error: Invalid tap name: 'homebrew/foo/bar'}).to_stderr
      .and raise_error(SystemExit)
  end

  it "continues untapping remaining taps when uninstallation is declined" do
    tap1 = Tap.fetch("homebrew", "foo")
    tap2 = Tap.fetch("homebrew", "bar")

    cmd = described_class.new(["homebrew/foo", "homebrew/bar"])
    allow(cmd.args.named).to receive(:to_installed_taps).and_return([tap1, tap2])

    formula = instance_double(Formula, full_name: "homebrew/foo/testball")
    allow(cmd).to receive(:installed_formulae_for).with(tap: tap1).and_return([formula])
    allow(cmd).to receive(:installed_formulae_for).with(tap: tap2).and_return([])
    allow(cmd).to receive(:installed_casks_for).with(tap: tap1).and_return([])
    allow(cmd).to receive(:installed_casks_for).with(tap: tap2).and_return([])

    expect(tap1).not_to receive(:uninstall)
    allow(Homebrew::Ask).to receive(:confirm?)
      .with(action: "changes")
      .and_raise(SystemExit)
    expect(tap2).to receive(:uninstall).with(manual: true)

    expect { cmd.run }
      .to output(/Refusing to untap.*following installed formulae:/m).to_stderr
      .and output(%r{Would untap homebrew/foo after uninstalling the following formulae.*testball}m).to_stdout
    expect(Homebrew).to have_failed
  ensure
    Homebrew.failed = false
  end

  it "lists installed packages before offering to uninstall them and untap" do
    tap = Tap.fetch("homebrew", "foo")
    rack = HOMEBREW_CELLAR/"testball"
    keg = instance_double(Keg, rack:, tab: instance_double(Tab, tap:))
    formula = instance_double(
      Formula,
      full_name:      "homebrew/foo/testball",
      installed_kegs: [keg],
      to_s:           "homebrew/foo/testball",
    )
    cask = instance_double(Cask::Cask, full_name: "homebrew/foo/testcask", token: "testcask")
    cmd = described_class.new(["homebrew/foo"])

    allow(cmd.args.named).to receive(:to_installed_taps).and_return([tap])
    allow(cmd).to receive(:installed_formulae_for).with(tap:).and_return([formula], [])
    allow(cmd).to receive(:installed_casks_for).with(tap:).and_return([cask], [])
    allow(Homebrew::Ask).to receive(:confirm?)
      .with(action: "changes")
      .and_return(true)

    named_args = [formula.full_name, cask.full_name]
    expect(Cask::Uninstall).to receive(:check_dependent_casks).with(cask, named_args:).ordered
    expect(Homebrew::Uninstall).to receive(:uninstall_kegs)
      .with({ rack => [keg] }, casks: [cask], force: false, named_args:).ordered
    expect(Cask::Uninstall).to receive(:uninstall_casks).with(cask, force: false)
    expect(tap).to receive(:uninstall).with(manual: true)

    expect { cmd.run }.to output(<<~EOS).to_stdout
      ==> Would untap homebrew/foo after uninstalling the following formulae and casks:
      homebrew/foo/testball
      homebrew/foo/testcask
    EOS
  end

  it "force-uninstalls installed packages without prompting before untapping" do
    tap = Tap.fetch("homebrew", "foo")
    rack = HOMEBREW_CELLAR/"testball"
    keg = instance_double(Keg, rack:, tab: instance_double(Tab, tap:))
    formula = instance_double(
      Formula,
      full_name:      "homebrew/foo/testball",
      installed_kegs: [keg],
    )
    cask = instance_double(Cask::Cask, full_name: "homebrew/foo/testcask")
    cmd = described_class.new(["--force", "homebrew/foo"])

    allow(cmd.args.named).to receive(:to_installed_taps).and_return([tap])
    allow(cmd).to receive(:installed_formulae_for).with(tap:).and_return([formula], [])
    allow(cmd).to receive(:installed_casks_for).with(tap:).and_return([cask], [])
    expect(Homebrew::Ask).not_to receive(:confirm?)

    named_args = [formula.full_name, cask.full_name]
    expect(Cask::Uninstall).to receive(:check_dependent_casks).with(cask, named_args:).ordered
    expect(Homebrew::Uninstall).to receive(:uninstall_kegs)
      .with({ rack => [keg] }, casks: [cask], force: true, named_args:).ordered
    expect(Cask::Uninstall).to receive(:uninstall_casks).with(cask, force: true)
    expect(tap).to receive(:uninstall).with(manual: true)

    expect { cmd.run }.not_to output.to_stdout
  end

  it "does not untap when an installation remains" do
    tap = Tap.fetch("homebrew", "foo")
    cask = instance_double(Cask::Cask, full_name: "homebrew/foo/testcask", token: "testcask")
    cmd = described_class.new(["homebrew/foo"])

    allow(cmd.args.named).to receive(:to_installed_taps).and_return([tap])
    allow(cmd).to receive(:installed_formulae_for).with(tap:).and_return([], [])
    allow(cmd).to receive(:installed_casks_for).with(tap:).and_return([cask], [cask])
    allow(Homebrew::Ask).to receive(:confirm?)
      .with(action: "changes")
      .and_return(true)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Cask::Uninstall).to receive(:uninstall_casks)
    expect(tap).not_to receive(:uninstall)

    expect { cmd.run }.to output(%r{Failed to fully uninstall casks from homebrew/foo}).to_stderr
    expect(Homebrew).to have_failed
  ensure
    Homebrew.failed = false
  end

  describe "#installed_formulae_for" do
    shared_examples "finds installed formulae in tap", :no_api do
      def load_formula(name:, with_formula_file: false, mock_install: false)
        formula = if with_formula_file
          path = Formulary.find_formula_in_tap(name, subject)
          path.dirname.mkpath
          path.write <<~RUBY
            class #{Formulary.class_s(name)} < Formula
              url "https://brew.sh/#{name}-1.0.tgz"
            end
          RUBY
          subject.clear_cache
          Formulary.factory(path)
        else
          formula(name, tap: subject) do
            T.bind(self, T.class_of(Formula))
            url "https://brew.sh/#{name}-1.0.tgz"
          end
        end

        if mock_install
          keg_path = HOMEBREW_CELLAR/name/"1.2.3"
          keg_path.mkpath

          tab_path = keg_path/AbstractTab::FILENAME
          tab_path.write <<~JSON
            {
              "source": {
                "tap": "#{subject}"
              }
            }
          JSON
        end

        formula
      end

      let!(:currently_installed_formula) do
        load_formula(name: "current_install", with_formula_file: true, mock_install: true)
      end

      before do
        # Formula that is available from a subject but not installed.
        load_formula(name: "no_install", with_formula_file: true)

        # Formula that was installed from a subject but is no longer available from that subject.
        load_formula(name: "legacy_install", mock_install: true)

        subject.clear_cache
      end

      it "returns the expected formulae" do
        expect(described_class.new(%w[arg1]).installed_formulae_for(tap: subject).map(&:full_name))
          .to eq([currently_installed_formula.full_name])
      end

      it "ignores formulae with invalid specs" do
        path = Formulary.find_formula_in_tap("invalid-spec", subject)
        path.dirname.mkpath
        path.write <<~RUBY
          class InvalidSpec < Formula
          end
        RUBY
        keg_path = HOMEBREW_CELLAR/"invalid-spec"/"1.2.3"
        keg_path.mkpath

        (keg_path/AbstractTab::FILENAME).write <<~JSON
          {
            "source": {
              "tap": "#{subject}"
            }
          }
        JSON
        subject.clear_cache

        expect(described_class.new(%w[arg1]).installed_formulae_for(tap: subject).map(&:full_name))
          .to eq([currently_installed_formula.full_name])
      end
    end

    context "with core tap" do
      subject(:tap) { CoreTap.instance }

      include_examples "finds installed formulae in tap"
    end

    context "with non-core tap" do
      subject(:tap) { Tap.fetch("homebrew", "foo") }

      before do
        tap.formula_dir.mkpath
      end

      include_examples "finds installed formulae in tap"
    end
  end

  describe "#installed_casks_for", :cask do
    shared_examples "finds installed casks in tap", :no_api do
      def load_cask(token:, with_cask_file: false, mock_install: false, deprecated: false)
        cask_source = <<~RUBY
          cask '#{token}' do
            version "1.2.3"
            sha256 :no_check

            url 'https://brew.sh/'

            #{"raise MethodDeprecatedError" if deprecated}
          end
        RUBY

        if with_cask_file
          cask_path = subject.cask_dir/"#{token}.rb"
          cask_path.parent.mkpath
          cask_path.write cask_source
        end

        return if deprecated

        cask_loader = Cask::CaskLoader::FromContentLoader.new(cask_source, tap: subject)
        cask = cask_loader.load(config: nil)

        InstallHelper.install_with_caskfile(cask) if mock_install

        cask
      end

      let!(:currently_installed_cask) do
        load_cask(token: "current_install", with_cask_file: true, mock_install: true)
      end

      before do
        # Cask that is available from a subject but not installed.
        load_cask(token: "no_install", with_cask_file: true)

        # Cask that was installed from a subject but is no longer available from that subject.
        load_cask(token: "legacy_install", mock_install: true)

        # Cask that uses deprecated method.
        load_cask(token: "deprecated_method", with_cask_file: true, deprecated: true)
      end

      it "returns the expected casks" do
        expect(described_class.new(%w[arg1]).installed_casks_for(tap: subject)).to eq([currently_installed_cask])
      end
    end

    context "with core cask tap" do
      subject(:tap) { CoreCaskTap.instance }

      include_examples "finds installed casks in tap"
    end

    context "with non-core cask tap" do
      subject(:tap) { Tap.fetch("homebrew", "foo") }

      include_examples "finds installed casks in tap"
    end
  end
end
