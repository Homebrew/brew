# typed: true
# frozen_string_literal: true

require "style"

RSpec.describe Homebrew::Style do
  around do |example|
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH, HOMEBREW_LIBRARY/"Homebrew"
    FileUtils.ln_s HOMEBREW_LIBRARY_PATH.parent/".rubocop.yml", HOMEBREW_LIBRARY/".rubocop.yml"

    example.run
  ensure
    FileUtils.rm_f HOMEBREW_LIBRARY/"Homebrew"
    FileUtils.rm_f HOMEBREW_LIBRARY/".rubocop.yml"
  end

  before do
    allow(Homebrew).to receive(:install_bundler_gems!)
  end

  describe ".check_style_json" do
    let(:dir) { mktmpdir }

    it "returns offenses when RuboCop reports offenses" do
      formula = dir/"my-formula.rb"

      formula.write <<~RUBY
        class MyFormula < Formula

        end
      RUBY

      style_offenses = described_class.check_style_json([formula])

      expect(style_offenses.for_path(formula.realpath).map(&:message))
        .to include("Extra empty line detected at class body beginning.")
    end
  end

  describe ".check_style_and_print" do
    let(:dir) { mktmpdir }

    it "returns true (success) for conforming file with only audit-level violations" do
      # This file is known to use non-rocket hashes and other things that trigger audit,
      # but not regular, cop violations
      target_file = HOMEBREW_LIBRARY_PATH/"utils.rb"

      style_result = described_class.check_style_and_print([target_file])

      expect(style_result).to be true
    end
  end

  describe ".run_actionlint!" do
    let(:actionlint_result) do
      instance_double(SystemCommand::Result, success?: true, stdout: "", stderr: "")
    end

    before do
      allow(described_class).to receive_messages(actionlint: "actionlint", shellcheck: "shellcheck")
      allow(Tty).to receive(:color?).and_return(false)
      allow(described_class).to receive(:system_command).and_return(actionlint_result)
    end

    it "uses a tap's actionlint config when present" do
      tap_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      workflows_dir = tap_path/".github/workflows"
      workflows_dir.mkpath
      workflow = workflows_dir/"ci.yml"
      workflow.write "name: CI"

      tap_config = tap_path/".github/actionlint.yaml"
      tap_config.write "self-hosted-runner:\n  labels: []\n"

      expect(described_class).to receive(:system_command).with(
        "actionlint",
        args:         ["-shellcheck", "shellcheck",
                       "-config-file", tap_config,
                       "-ignore", "image: string; options: string",
                       "-ignore", "label .* is unknown",
                       workflow],
        print_stderr: false,
      ).and_return(actionlint_result)

      described_class.run_actionlint!([workflow])
    end

    it "falls back to HOMEBREW_REPOSITORY config when no tap config exists" do
      tap_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      workflows_dir = tap_path/".github/workflows"
      workflows_dir.mkpath
      workflow = workflows_dir/"ci.yml"
      workflow.write "name: CI"

      expect(described_class).to receive(:system_command).with(
        "actionlint",
        args:         ["-shellcheck", "shellcheck",
                       "-config-file", HOMEBREW_REPOSITORY/".github/actionlint.yaml",
                       "-ignore", "image: string; options: string",
                       "-ignore", "label .* is unknown",
                       workflow],
        print_stderr: false,
      ).and_return(actionlint_result)

      described_class.run_actionlint!([workflow])
    end

    it "falls back to HOMEBREW_REPOSITORY config when files span multiple taps" do
      tap1_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      (tap1_path/".github/workflows").mkpath
      (tap1_path/".github/actionlint.yaml").write "self-hosted-runner:\n  labels: []\n"
      workflow1 = tap1_path/".github/workflows/ci.yml"
      workflow1.write "name: CI"

      tap2_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-bar"
      (tap2_path/".github/workflows").mkpath
      (tap2_path/".github/actionlint.yaml").write "self-hosted-runner:\n  labels: []\n"
      workflow2 = tap2_path/".github/workflows/ci.yml"
      workflow2.write "name: CI"

      expect(described_class).to receive(:system_command).with(
        "actionlint",
        args:         ["-shellcheck", "shellcheck",
                       "-config-file", HOMEBREW_REPOSITORY/".github/actionlint.yaml",
                       "-ignore", "image: string; options: string",
                       "-ignore", "label .* is unknown",
                       workflow1, workflow2],
        print_stderr: false,
      ).and_return(actionlint_result)

      described_class.run_actionlint!([workflow1, workflow2])
    end
  end

  describe ".shellcheck" do
    it "uses a matching system shellcheck" do
      formula = instance_double(Formula)

      allow(Formula).to receive(:[]).with("shellcheck").and_return(formula)
      allow(formula).to receive(:ensure_installed!).with(latest:     true,
                                                         reason:     "shell style checks",
                                                         executable: "shellcheck")
                                                   .and_return(Pathname.new("/usr/bin/shellcheck"))

      expect(described_class.shellcheck).to eq(Pathname.new("/usr/bin/shellcheck"))
    end
  end

  describe ".actionlint" do
    it "uses a matching system actionlint" do
      formula = instance_double(Formula)

      allow(Formula).to receive(:[]).with("actionlint").and_return(formula)
      allow(formula).to receive(:ensure_installed!).with(latest:       true,
                                                         reason:       "GitHub Actions checks",
                                                         executable:   "actionlint",
                                                         version_args: ["-version"])
                                                   .and_return(Pathname.new("/usr/bin/actionlint"))

      expect(described_class.actionlint).to eq(Pathname.new("/usr/bin/actionlint"))
    end
  end

  describe ".run_shfmt!" do
    it "passes a matching system shfmt to the shfmt wrapper" do
      shell_file = Pathname.new("/tmp/test.sh")
      formula = instance_double(Formula)

      allow(Formula).to receive(:[]).with("shfmt").and_return(formula)
      allow(formula).to receive(:ensure_installed!).with(latest:     true,
                                                         reason:     "formatting shell scripts",
                                                         executable: "shfmt")
                                                   .and_return(Pathname.new("/usr/bin/shfmt"))

      shfmt_result = instance_double(SystemCommand::Result, success?: true, stdout: "", stderr: "")
      expect(described_class).to receive(:system_command).with(
        HOMEBREW_LIBRARY/"Homebrew/utils/shfmt.sh",
        args:         ["--language-dialect", "bash", "--indent", "2", "--case-indent", "--", shell_file],
        env:          { "HOMEBREW_SHFMT" => "/usr/bin/shfmt" },
        print_stderr: false,
      ).and_return(shfmt_result)

      expect(described_class.run_shfmt!([shell_file])).to be true
    end
  end

  describe ".run_shellcheck" do
    it "runs shellcheck in parallel chunks and merges their JSON results" do
      dir = mktmpdir
      log = dir/"shellcheck-args.log"
      fake_shellcheck = dir/"shellcheck"
      fake_shellcheck.write <<~SCRIPT
        #!/bin/bash
        echo "$*" >> "#{log}"
        echo "[]"
      SCRIPT
      fake_shellcheck.chmod 0755

      files = (1..3).map do |i|
        file = dir/"script#{i}.sh"
        file.write "#!/bin/bash\n"
        file
      end

      allow(Hardware::CPU).to receive(:cores).and_return(2)

      offenses = described_class.run_shellcheck(files, :json, shellcheck_path: fake_shellcheck)

      expect(offenses).to eq []
      chunks = log.read.lines
      expect(chunks.length).to eq 2
      first_chunk = chunks.find { |chunk| chunk.include?("script1.sh") }
      expect(first_chunk).to include("script2.sh")
      expect(first_chunk).not_to include("script3.sh")
    end
  end

  describe ".run_rubocop" do
    let(:dir) { mktmpdir }
    let(:ruby_file) { dir/"test.rb" }

    before do
      ruby_file.write <<~RUBY
        class Test
        end
      RUBY
    end

    it "passes --disable-uncorrectable when --todo is enabled" do
      result = double(status: double(exitstatus: 0), stdout: '{"files":[]}')

      expect(described_class).to receive(:system_command) do |_cmd, args:, **|
        expect(args).to include("--disable-uncorrectable")
        result
      end

      described_class.run_rubocop([ruby_file], :json, fix: true, todo: true)
    end
  end
end
