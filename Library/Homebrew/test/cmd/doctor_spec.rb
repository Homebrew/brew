# typed: strict
# frozen_string_literal: true

require "cmd/doctor"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Doctor do
  it_behaves_like "parseable arguments"

  specify "check_integration_test", :integration_test do
    expect { brew "doctor", "check_integration_test" }
      .to output(/This is an integration test/).to_stderr
  end

  specify "check_missing_deps reports formula and cask dependencies", :cask do
    formula = instance_double(Formula, full_name:            "needs-foo",
                                       missing_dependencies: [instance_double(Dependency, to_s: "foo")])
    cask = instance_double(Cask::Cask, full_name: "with-depends-on-everything")
    tab = instance_double(Cask::Tab, runtime_dependencies: {
      "cask"    => [{ "full_name" => "local-caffeine" }],
      "formula" => [{ "full_name" => "unar" }],
    })
    HOMEBREW_CELLAR.mkpath
    allow(Formula).to receive(:installed).and_return([formula])
    allow(Cask::Caskroom).to receive(:casks).and_return([cask])
    allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)

    expect(Homebrew::Diagnostic::Checks.new.check_missing_deps)
      .to include(
        "Some installed formulae or casks are missing dependencies.",
        "brew install foo local-caffeine unar",
        "Run `brew missing` for more details.",
      )
  end

  specify "check_for_unreadable_installed_formula skips untrusted installed formulae" do
    rack = HOMEBREW_CELLAR/"php@7.2"
    rack.mkpath
    (rack/"1.0").mkpath
    allow(Formulary).to receive(:from_rack)
      .with(rack)
      .and_raise(
        Homebrew::UntrustedTapError,
        "Refusing to load formula shivammathur/php/php@7.2.",
      )

    expect(Homebrew::Diagnostic::Checks.new.check_for_unreadable_installed_formula).to be_nil
  end

  specify "does not print removed caveats method errors for installed casks", :cask do
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    installer = InstallHelper.install_with_caskfile(cask)
    installed_caskfile = installer.metadata_subdir/"#{cask.token}.rb"
    expect(installed_caskfile).to exist

    installed_caskfile.write(
      installed_caskfile.read.sub(
        /\nend\n\z/,
        <<~RUBY,
            caveats do
              discontinued
            end
          end
        RUBY
      ),
    )

    (CoreCaskTap.instance.cask_dir/"local-caffeine.rb").unlink
    CoreCaskTap.instance.clear_cache

    cmd = described_class.new(["check_cask_deprecated_disabled"])

    expect { cmd.run }
      .to not_to_output(/Unexpected method 'discontinued' called during caveats on Cask local-caffeine\./).to_stderr
  end
end
