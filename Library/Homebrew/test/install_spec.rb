# typed: strict
# frozen_string_literal: true

require "install"
require "dependency"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::Install do
  specify "::perform_preinstall_checks runs non-fatal preinstall diagnostics" do
    allow(described_class).to receive(:check_prefix)
    allow(described_class).to receive(:check_cpu)
    allow(described_class).to receive(:attempt_directory_creation)

    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:supported_configuration_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:preinstall_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:fatal_preinstall_checks)
      .ordered

    described_class.send(:perform_preinstall_checks)
  end

  describe "::print_dry_run_dependencies" do
    it "splits fresh installs and upgrades under separate headers" do
      fresh = formula("fresh-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      installed = formula("installed-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(fresh).to receive(:any_version_installed?).and_return(false)
      allow(installed).to receive(:any_version_installed?).and_return(true)
      deps = [
        instance_double(Dependency, to_formula: fresh),
        instance_double(Dependency, to_formula: installed),
      ]

      expect { described_class.print_dry_run_dependencies(Testball.new, deps, &:name) }
        .to output(/Would install 1 dependency.*fresh-dep.*Would upgrade 1 dependency.*installed-dep/m).to_stdout
    end
  end
end
