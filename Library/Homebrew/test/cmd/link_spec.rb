# typed: false
# frozen_string_literal: true

require "cmd/link"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Link do
  it_behaves_like "parseable arguments"

  it "uses formula-aware conflict handling when linking a Formula" do
    formula = formula "testball" do
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
    it "does not print keg-only output when linking a #{formula_type} formula", :integration_test do
      formula_content = <<~RUBY
        keg_only :versioned_formula

        def caveats
          "unexpected caveat output"
        end

        def post_install
          puts "unexpected post_install output"
        end
      RUBY

      setup_test_formula formula_name, formula_content, tab_attributes: { installed_on_request: true }
      Formula[formula_name].bin.mkpath
      FileUtils.touch Formula[formula_name].bin/"link-output-test"
      Formula[formula_name].any_installed_keg.unlink
      unexpected_output = /unexpected caveat output|unexpected post_install output|
                           If you need to have this software first in your PATH|keg-only/x

      expect { brew "link", formula_name }
        .to not_to_output(unexpected_output).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(HOMEBREW_PREFIX/"bin/link-output-test").to be_a_file
    end
  end
end
