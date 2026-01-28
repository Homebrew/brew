# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test"
require "sandbox"

RSpec.describe Homebrew::DevCmd::Test do
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

  it "blocks network access when test phase is offline", :integration_test do
    if Sandbox.available?
      install_test_formula "testball_offline_test", <<~RUBY
        deny_network_access! :test
        test do
          system "curl", "example.org"
        end
      RUBY

      expect { brew "test", "--verbose", "testball_offline_test" }
        .to output(/curl: \(6\) Could not resolve host: example\.org/).to_stdout
        .and be_a_failure
    end
  end
end
