# typed: strict
# frozen_string_literal: true

require "cmd/help"
require "cmd/shared_examples/args_parse"
require "trust"

RSpec.describe Homebrew::Cmd::HelpCmd, :integration_test do
  it_behaves_like "parseable arguments"

  describe "help" do
    it "prints help for a documented Ruby command" do
      expect { brew "help", "cat" }
        .to output(/^Usage: brew cat/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    it "prints the originating tap for an external command from a third-party tap" do
      tap_path = HOMEBREW_TAP_DIRECTORY/"trusthelp/homebrew-foo"
      tap_path.mkpath
      tap_path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/trusthelp/homebrew-foo"
        FileUtils.touch "readme"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end
      cmd_path = tap_path/"cmd/hello-trust-tap.rb"
      cmd_path.dirname.mkpath
      cmd_path.write <<~RUBY
        # typed: strict
        # frozen_string_literal: true

        raise "leaked SECRET_TOKEN" if ENV["SECRET_TOKEN"]

        require "abstract_command"

        module Homebrew
          module Cmd
            class HelloTrustTap < AbstractCommand
              cmd_args do
                description "A friendly greeter from a tap."
              end

              sig { override.void }
              def run; end
            end
          end
        end
      RUBY
      cmd_path.chmod(0755)

      expect do
        brew "help", "hello-trust-tap", "SECRET_TOKEN" => "password", "HOMEBREW_NO_REQUIRE_TAP_TRUST" => "1"
      end
        .to output(%r{^From tap: trusthelp/foo$}).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"trusthelp"
    end

    it "requires trust for an external command from a third-party tap" do
      tap_path = HOMEBREW_TAP_DIRECTORY/"trusthelp/homebrew-foo"
      tap_path.mkpath
      tap_path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/trusthelp/homebrew-foo"
        FileUtils.touch "readme"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end
      cmd_path = tap_path/"cmd/hello-trust-tap.rb"
      cmd_path.dirname.mkpath
      cmd_path.write <<~RUBY
        # typed: strict
        # frozen_string_literal: true

        require "abstract_command"

        module Homebrew
          module Cmd
            class HelloTrustTap < AbstractCommand
              cmd_args do
                description "A friendly greeter from a tap."
              end

              sig { override.void }
              def run; end
            end
          end
        end
      RUBY
      cmd_path.chmod(0755)
      trust_home = Pathname(TEST_TMPDIR)/"help-command-trust"
      trust_env = { "HOMEBREW_USER_CONFIG_HOME" => trust_home.to_s }
      require_trust_env = trust_env.merge(
        "HOMEBREW_REQUIRE_TAP_TRUST" => "1",
      )

      expect { brew "help", "hello-trust-tap", require_trust_env.dup }
        .to output(%r{trusthelp/foo}).to_stderr
        .and be_a_failure

      expect { brew "trust", "--command", "trusthelp/foo/hello-trust-tap", trust_env.dup }
        .to output(%r{Trusted command: trusthelp/foo/hello-trust-tap}).to_stdout
        .and be_a_success

      expect { brew "help", "hello-trust-tap", require_trust_env.dup }
        .to output(%r{^From tap: trusthelp/foo$}).to_stdout
        .and be_a_success
    ensure
      FileUtils.rm_rf trust_home if trust_home
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"trusthelp"
    end

    it "does not print the originating tap for an external command from an official tap" do
      tap_path = setup_test_tap
      cmd_path = tap_path/"cmd/hello-tap.rb"
      cmd_path.dirname.mkpath
      cmd_path.write <<~RUBY
        # typed: strict
        # frozen_string_literal: true

        require "abstract_command"

        module Homebrew
          module Cmd
            class HelloTap < AbstractCommand
              cmd_args do
                description "A friendly greeter from a tap."
              end

              sig { override.void }
              def run; end
            end
          end
        end
      RUBY
      cmd_path.chmod(0755)

      expect { brew "help", "hello-tap" }
        .not_to output(/^From tap:/).to_stdout
    end

    it "runs an external command's own `--help` when it has no `#:` comments" do
      tap_path = setup_test_tap
      cmd_path = tap_path/"cmd/brew-selfdoc"
      cmd_path.dirname.mkpath
      cmd_path.write <<~SH
        #!/bin/bash
        [[ "$*" == *--help* ]] || { echo "expected --help, got: $*" >&2; exit 1; }
        echo "Usage: brew selfdoc [options]"
      SH
      cmd_path.chmod(0755)

      expect { brew "help", "selfdoc" }
        .to output(/^Usage: brew selfdoc/).to_stdout
        .and be_a_success
    end

    it "renders `#:` help for an external command rather than running it" do
      tap_path = setup_test_tap
      cmd_path = tap_path/"cmd/brew-commented"
      cmd_path.dirname.mkpath
      cmd_path.write <<~SH
        #!/bin/bash
        #:  * `commented`:
        #:    Documented via comments.
        echo "the command body should not have run" >&2
        exit 1
      SH
      cmd_path.chmod(0755)

      expect { brew "help", "commented" }
        .to output(/Documented via comments\./).to_stdout
        .and be_a_success
    end
  end

  describe "cat" do
    it "prints help when no argument is given" do
      expect { brew "cat" }
        .to output(/^Usage: brew cat/).to_stderr
        .and not_to_output.to_stdout
        .and be_a_failure
    end
  end
end
