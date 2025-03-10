# frozen_string_literal: true

require "extend/ENV"
require "cmd/reinstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Reinstall do
  it_behaves_like "parseable arguments"

  it "reinstalls a Formula", :integration_test do
    install_test_formula "testball"
    foo_dir = HOMEBREW_CELLAR/"testball/0.1/bin"
    expect(foo_dir).to exist
    FileUtils.rm_r(foo_dir)

    expect { brew "reinstall", "testball" }
      .to output(/Reinstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    expect(foo_dir).to exist
  end

  it "reinstalls a Formula with ask input", :integration_test do
    install_test_formula "testball"
    foo_dir = HOMEBREW_CELLAR/"testball/0.1/bin"
    expect(foo_dir).to exist
    FileUtils.rm_r(foo_dir)

    expect { brew "reinstall", "--ask", "testball" }
      .to output(/.*Formula\s*\(1\):\s*testball.*/).to_stdout
                                                   .and not_to_output.to_stderr
                                                                     .and be_a_success

    expect(foo_dir).to exist
  end
end
