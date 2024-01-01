# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew test" do
  it_behaves_like "parseable arguments"

  it "tests a given Formula", :integration_test do
    install_test_formula "testball", <<~'RUBY'
      test do
        assert_equal "test", shell_output("#{bin}/test")
      end
    RUBY

    expect { brew "test", "--verbose", "testball" }
      .to output(/Testing testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
