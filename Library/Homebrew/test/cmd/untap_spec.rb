# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/untap"

RSpec.describe Homebrew::Cmd::Untap do
  let(:class_instance) { described_class.new(%w[arg1]) }

  it_behaves_like "parseable arguments"

  it "untaps a given Tap", :integration_test do
    setup_test_tap

    expect { brew "untap", "homebrew/foo" }
      .to output(/Untapped/).to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end

  it "fails without a traceback when given a formula name" do
    expect { described_class.new(["homebrew/foo/bar"]).run }
      .to output(%r{Error: Invalid tap name: 'homebrew/foo/bar'}).to_stderr
      .and raise_error(SystemExit)
  end

  it "continues untapping remaining taps when one has installed formulae" do
    tap1 = Tap.fetch("homebrew", "foo")
    tap2 = Tap.fetch("homebrew", "bar")

    cmd = described_class.new(["homebrew/foo", "homebrew/bar"])
    allow(cmd.args.named).to receive(:to_installed_taps).and_return([tap1, tap2])

    allow(cmd).to receive(:installed_formulae_for).with(tap: tap1).and_return(["homebrew/foo/testball"])
    allow(cmd).to receive(:installed_formulae_for).with(tap: tap2).and_return([])
    allow(cmd).to receive(:installed_casks_for).with(tap: tap1).and_return([])
    allow(cmd).to receive(:installed_casks_for).with(tap: tap2).and_return([])

    expect(tap1).not_to receive(:uninstall)
    expect(tap2).to receive(:uninstall).with(manual: true)

    expect { cmd.run }.to output(/Refusing to untap/).to_stderr
    expect(Homebrew).to have_failed
  ensure
    Homebrew.failed = false
  end

  describe "#installed_formulae_for" do
    shared_examples "finds installed formulae in tap", :no_api do
      def load_formula(name:, with_formula_file: false, mock_install: false)
        formula = if with_formula_file
          path = Formulary.find_formula_in_tap(name, tap)
          path.dirname.mkpath
          path.write <<~RUBY
            class #{Formulary.class_s(name)} < Formula
              url "https://brew.sh/#{name}-1.0.tgz"
            end
          RUBY
          tap.clear_cache
          Formulary.factory(path)
        else
          formula(name, tap:) do
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
                "tap": "#{tap}"
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
        # Formula that is available from a tap but not installed.
        load_formula(name: "no_install", with_formula_file: true)

        # Formula that was installed from a tap but is no longer available from that tap.
        load_formula(name: "legacy_install", mock_install: true)

        tap.clear_cache
      end

      it "returns the expected formulae" do
        expect(class_instance.installed_formulae_for(tap:).map(&:full_name))
          .to eq([currently_installed_formula.full_name])
      end

      it "ignores formulae with invalid specs" do
        path = Formulary.find_formula_in_tap("invalid-spec", tap)
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
              "tap": "#{tap}"
            }
          }
        JSON
        tap.clear_cache

        expect(class_instance.installed_formulae_for(tap:).map(&:full_name))
          .to eq([currently_installed_formula.full_name])
      end
    end

    context "with core tap" do
      let(:tap) { CoreTap.instance }

      include_examples "finds installed formulae in tap"
    end

    context "with non-core tap" do
      let(:tap) { Tap.fetch("homebrew", "foo") }

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
          cask_path = tap.cask_dir/"#{token}.rb"
          cask_path.parent.mkpath
          cask_path.write cask_source
        end

        return if deprecated

        cask_loader = Cask::CaskLoader::FromContentLoader.new(cask_source, tap:)
        cask = cask_loader.load(config: nil)

        InstallHelper.install_with_caskfile(cask) if mock_install

        cask
      end

      let!(:currently_installed_cask) do
        load_cask(token: "current_install", with_cask_file: true, mock_install: true)
      end

      before do
        # Cask that is available from a tap but not installed.
        load_cask(token: "no_install", with_cask_file: true)

        # Cask that was installed from a tap but is no longer available from that tap.
        load_cask(token: "legacy_install", mock_install: true)

        # Cask that uses deprecated method.
        load_cask(token: "deprecated_method", with_cask_file: true, deprecated: true)
      end

      it "returns the expected casks" do
        expect(class_instance.installed_casks_for(tap:)).to eq([currently_installed_cask])
      end
    end

    context "with core cask tap" do
      let(:tap) { CoreCaskTap.instance }

      include_examples "finds installed casks in tap"
    end

    context "with non-core cask tap" do
      let(:tap) { Tap.fetch("homebrew", "foo") }

      include_examples "finds installed casks in tap"
    end
  end
end
