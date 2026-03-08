# frozen_string_literal: true

require "cask/staged"
require "cask/cask"
require "cask/config"
require "cask/dsl/postflight"

RSpec.describe Cask::Staged, :cask do
  subject(:staged) { described_class.new(cask) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:config) { cask.config }

  let(:described_class) do
    Class.new(Cask::DSL::Postflight)
  end

  describe "#generate_completions_from_executable" do
    let(:executable) do
      (mktmpdir/"test-cli").tap do |path|
        path.write <<~BASH
          #!/bin/bash
          case "$1" in
            completion)
              case "$2" in
                bash) echo "# bash completion for test-cli" ;;
                zsh) echo "#compdef test-cli" ;;
                fish) echo "# fish completion for test-cli" ;;
                powershell) echo "# pwsh completion for test-cli" ;;
              esac
              ;;
          esac
        BASH
        FileUtils.chmod "+x", path
      end
    end

    after do
      staged.remove_generated_completions("test-cli")
    end

    it "generates completion scripts for bash, zsh, and fish by default" do
      staged.generate_completions_from_executable(executable, "completion", base_name: "test-cli")

      expect(config.bash_completion/"test-cli").to be_a_file
      expect(config.zsh_completion/"_test-cli").to be_a_file
      expect(config.fish_completion/"test-cli.fish").to be_a_file
    end

    it "generates completion scripts with correct content" do
      staged.generate_completions_from_executable(executable, "completion", base_name: "test-cli")

      expect((config.bash_completion/"test-cli").read).to include("bash completion")
      expect((config.zsh_completion/"_test-cli").read).to include("#compdef")
      expect((config.fish_completion/"test-cli.fish").read).to include("fish completion")
    end

    it "generates pwsh completions when :cobra format is used" do
      staged.generate_completions_from_executable(
        executable,
        base_name:              "test-cli",
        shell_parameter_format: :cobra,
      )

      expect(config.pwsh_completion/"_test-cli.ps1").to be_a_file
      expect((config.pwsh_completion/"_test-cli.ps1").read).to include("pwsh completion")
    end

    it "uses cask token as default base_name" do
      staged.generate_completions_from_executable(executable, "completion")

      expect(config.bash_completion/cask.token).to be_a_file

      staged.remove_generated_completions(cask.token)
    end

    it "respects custom shells parameter" do
      staged.generate_completions_from_executable(
        executable,
        "completion",
        base_name: "test-cli",
        shells:    [:zsh],
      )

      expect(config.bash_completion/"test-cli").not_to exist
      expect(config.zsh_completion/"_test-cli").to be_a_file
      expect(config.fish_completion/"test-cli.fish").not_to exist
    end
  end

  describe "#remove_generated_completions" do
    let(:base_name) { "test-removal" }

    before do
      config.bash_completion.mkpath
      config.zsh_completion.mkpath
      config.fish_completion.mkpath
      config.pwsh_completion.mkpath

      (config.bash_completion/base_name).write("bash")
      (config.zsh_completion/"_#{base_name}").write("zsh")
      (config.fish_completion/"#{base_name}.fish").write("fish")
      (config.pwsh_completion/"_#{base_name}.ps1").write("pwsh")
    end

    it "removes all generated completion files" do
      staged.remove_generated_completions(base_name)

      expect(config.bash_completion/base_name).not_to exist
      expect(config.zsh_completion/"_#{base_name}").not_to exist
      expect(config.fish_completion/"#{base_name}.fish").not_to exist
      expect(config.pwsh_completion/"_#{base_name}.ps1").not_to exist
    end

    it "does not fail if files do not exist" do
      expect { staged.remove_generated_completions("nonexistent") }.not_to raise_error
    end
  end

  describe "shell_parameter_format options" do
    let(:executable) do
      (mktmpdir/"format-test").tap do |path|
        path.write <<~BASH
          #!/bin/bash
          echo "args: $@"
          echo "COMPLETE: $COMPLETE"
          echo "_FORMAT_TEST_COMPLETE: $_FORMAT_TEST_COMPLETE"
        BASH
        FileUtils.chmod "+x", path
      end
    end

    after do
      staged.remove_generated_completions("format-test")
    end

    it "passes shell name as plain argument by default" do
      staged.generate_completions_from_executable(
        executable,
        base_name: "format-test",
        shells:    [:bash],
      )

      content = (config.bash_completion/"format-test").read
      expect(content).to include("args: bash")
    end

    it "uses --shell=<shell> format with :arg" do
      staged.generate_completions_from_executable(
        executable,
        base_name:              "format-test",
        shell_parameter_format: :arg,
        shells:                 [:bash],
      )

      content = (config.bash_completion/"format-test").read
      expect(content).to include("--shell=bash")
    end

    it "uses COMPLETE env var with :clap" do
      staged.generate_completions_from_executable(
        executable,
        base_name:              "format-test",
        shell_parameter_format: :clap,
        shells:                 [:bash],
      )

      content = (config.bash_completion/"format-test").read
      expect(content).to include("COMPLETE: bash")
    end

    it "uses completion subcommand with :cobra" do
      staged.generate_completions_from_executable(
        executable,
        base_name:              "format-test",
        shell_parameter_format: :cobra,
        shells:                 [:bash],
      )

      content = (config.bash_completion/"format-test").read
      expect(content).to include("args: completion bash")
    end

    it "uses --<shell> flag with :flag" do
      staged.generate_completions_from_executable(
        executable,
        base_name:              "format-test",
        shell_parameter_format: :flag,
        shells:                 [:bash],
      )

      content = (config.bash_completion/"format-test").read
      expect(content).to include("--bash")
    end
  end
end
