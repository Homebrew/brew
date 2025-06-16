# frozen_string_literal: true

require "cmd/link"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Link do
  it_behaves_like "parseable arguments"

  it "links a given Formula", :integration_test do
    install_test_formula "testball"
    Formula["testball"].any_installed_keg.unlink

    expect { brew "link", "testball" }
      .to output(/Linking/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
