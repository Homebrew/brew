# typed: false
# frozen_string_literal: true

require "cmd/link"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Link do
  it_behaves_like "parseable arguments"

  it "uses formula-aware conflict handling when linking a Formula" do
    formula = formula "testball" do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"
    end
    keg = instance_double(Keg, rack: HOMEBREW_CELLAR/"testball", linked?: false, name: "testball")

    cmd = described_class.new(["testball"])
    allow(cmd.args.named).to receive(:to_latest_kegs).and_return([keg])
    allow(Formulary).to receive(:keg_only?).with(keg.rack).and_return(false)
    allow(keg).to receive(:to_formula).and_return(formula)
    expect(Homebrew::Unlink).to receive(:unlink_link_overwrite_formulae).with(formula, verbose: false)
    allow(keg).to receive(:lock).and_yield
    expect(keg).to receive(:link).with(dry_run: false, verbose: false, overwrite: false).and_return(1)

    expect { cmd.run }.to output(/Linking .*1 symlinks created\./).to_stdout
  end

  it "links a given Formula", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }
    Formula["testball"].any_installed_keg.unlink
    Formula["testball"].bin.mkpath
    FileUtils.touch Formula["testball"].bin/"testfile"

    expect { brew "link", "testball" }
      .to output(/Linking/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_PREFIX/"bin/testfile").to be_a_file
  end

  {
    "@-versioned" => "testball-link-output@1.0",
    "-full"       => "testball-link-output-full",
  }.each do |formula_type, formula_name|
    it "does not print keg-only output when linking a #{formula_type} formula" do
      test_formula = formula(formula_name) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/#{formula_name}-1.0"
        keg_only :versioned_formula

        def caveats
          "unexpected caveat output"
        end

        def post_install; end
      end
      keg = instance_double(
        Keg,
        rack:       HOMEBREW_CELLAR/formula_name,
        linked?:    false,
        name:       formula_name,
        to_formula: test_formula,
        to_s:       "#{formula_name}/1.0",
      )
      cmd = described_class.new([formula_name])

      allow(cmd.args.named).to receive(:to_latest_kegs).and_return([keg])
      allow(Formulary).to receive(:keg_only?).with(keg.rack).and_return(true)
      allow(Homebrew::Unlink).to receive(:unlink_link_overwrite_formulae)
      allow(keg).to receive(:lock).and_yield
      allow(keg).to receive(:link).and_return(1)
      unexpected_output = /unexpected caveat output|unexpected post_install output|
                           If you need to have this software first in your PATH|keg-only/x

      expect { cmd.run }
        .to not_to_output(unexpected_output).to_stdout
        .and not_to_output.to_stderr
    end
  end
end
