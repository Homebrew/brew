# frozen_string_literal: true

require "cmd/readall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::ReadallCmd do
  it_behaves_like "parseable arguments"

  it "imports all Formulae for a given Tap", :integration_test do
    formula_file = setup_test_formula "testball"

    alias_file = CoreTap.instance.alias_dir/"foobar"
    alias_file.parent.mkpath

    FileUtils.ln_s formula_file, alias_file

    expect { brew "readall", "--aliases", "--syntax", CoreTap.instance.name }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end
end
