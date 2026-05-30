# typed: false
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
      tap_path = HOMEBREW_TAP_DIRECTORY/"thirdparty/homebrew-foo"
      tap_path.mkpath
      tap_path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/thirdparty/homebrew-foo"
        FileUtils.touch "readme"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end
      cmd_path = tap_path/"cmd/hello-tap.rb"
      cmd_path.dirname.mkpath
      cmd_path.write <<~RUBY
        # typed: strict
        # frozen_string_literal: true

        raise "leaked SECRET_TOKEN" if ENV["SECRET_TOKEN"]

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

      expect { brew "help", "hello-tap", "SECRET_TOKEN" => "password" }
        .to output(%r{^From tap: thirdparty/foo$}).to_stdout
        .and output(%r{Tap thirdparty/foo was trusted by default}).to_stderr
        .and be_a_success
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "requires trust for an external command from a third-party tap" do
      tap_path = HOMEBREW_TAP_DIRECTORY/"thirdparty/homebrew-foo"
      tap_path.mkpath
      tap_path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/thirdparty/homebrew-foo"
        FileUtils.touch "readme"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end
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

      expect { brew "help", "hello-tap", "HOMEBREW_REQUIRE_TAP_TRUST" => "1" }
        .to output(%r{thirdparty/foo}).to_stderr
        .and be_a_failure

      expect { brew "trust", "--command", "thirdparty/foo/hello-tap" }
        .to output(%r{Trusted command: thirdparty/foo/hello-tap}).to_stdout
        .and be_a_success

      expect { brew "help", "hello-tap", "HOMEBREW_REQUIRE_TAP_TRUST" => "1" }
        .to output(%r{^From tap: thirdparty/foo$}).to_stdout
        .and be_a_success
    ensure
      Homebrew::Trust.clear!(:command)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
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
