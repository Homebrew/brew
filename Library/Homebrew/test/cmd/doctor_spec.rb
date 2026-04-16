# typed: false
# frozen_string_literal: true

require "cmd/doctor"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Doctor do
  it_behaves_like "parseable arguments"

  specify "check_integration_test", :integration_test do
    expect { brew "doctor", "check_integration_test" }
      .to output(/This is an integration test/).to_stderr
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
