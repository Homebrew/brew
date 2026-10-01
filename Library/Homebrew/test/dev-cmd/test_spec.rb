# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test"
require "sandbox"

RSpec.describe Homebrew::DevCmd::Test do
  define_negated_matcher :not_matching, :matching

  it_behaves_like "parseable arguments"

  it "tests a given Formula without process-listing warnings", :integration_test do
    skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?

    setup_test_formula "testball", <<~'RUBY', tab_attributes: { installed_on_request: true }
      test do
        assert_equal "test", shell_output("#{bin}/test")
        (logs/"testpath").write(testpath)
        require "socket"
        (testpath/"sockets").mkpath
        UNIXServer.open("sockets/test.sock") do
          UNIXSocket.open("sockets/test.sock", &:close)
        end
      end
    RUBY
    formula_prefix = Formula["testball"].prefix
    (formula_prefix/"bin").mkpath
    (formula_prefix/"bin/test").write <<~SH
      #!/bin/sh
      printf test
    SH
    (formula_prefix/"bin/test").chmod 0755
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/"testball").make_relative_symlink(formula_prefix)

    expect { brew "test", "--verbose", "testball", "HOMEBREW_NO_INSTALL_FROM_API" => "1" }
      .to output(a_string_matching(/Testing testball/)
        .and(not_matching(/sysmon request failed|pgrep: Cannot get process list/))).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    expect(Pathname((Formula["testball"].logs/"testpath").read)).not_to exist
  end

  it "blocks network access when test phase is offline", :integration_test, :needs_sandbox do
    skip "Sandbox not available." unless Sandbox.available?
    skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?

    formula_name = "testball_offline_test"
    setup_test_formula formula_name, <<~RUBY, tab_attributes: { installed_on_request: true }
      deny_network_access! :test
      test do
        require "socket"
        UNIXServer.open("test.sock") do
          UNIXSocket.open("test.sock", &:close)
        end
        system "curl", "example.org"
      end
    RUBY
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/formula_name).make_relative_symlink(Formula[formula_name].prefix)

    expect { brew "test", "--verbose", formula_name, "HOMEBREW_NO_INSTALL_FROM_API" => "1" }
      .to output(/curl: \((?:6\) Could not resolve host:|7\) Failed to connect to) example\.org/).to_stdout
      .and be_a_failure
  end
end
