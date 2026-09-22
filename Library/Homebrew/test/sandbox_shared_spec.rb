# typed: true
# frozen_string_literal: true

require "sandbox"
require "unpack_strategy"

RSpec.describe Sandbox do
  subject(:sandbox) { described_class.new }

  describe "::isolate_operation?" do
    before do
      ENV.delete("HOMEBREW_SANDBOX")
      allow(described_class).to receive(:isolate_operation?).and_call_original
    end

    it "ignores sandbox environment flags even when Homebrew is not writable" do
      ENV["HOMEBREW_SANDBOX"] = "1"
      ENV["HOMEBREW_AVOID_NESTED_SANDBOXING"] = "1"
      allow(described_class).to receive_messages(available?: true, nested_sandbox?: false)
      brew_file = mktmpdir/"brew"
      brew_file.write("unchanged")
      brew_file.chmod(0400)
      stub_const("HOMEBREW_BREW_FILE", brew_file)

      expect(described_class.isolate_operation?).to be(true)
    end

    it "inherits a sandbox only after checking that Homebrew is protected" do
      allow(IO).to receive(:new).with(198, autoclose: false).and_return($stdin)
      allow(File).to receive(:identical?).with($stdin, (HOMEBREW_LIBRARY_PATH/"sandbox.rb").to_s).and_return(true)
      allow(File).to receive(:open).with(HOMEBREW_BREW_FILE, File::WRONLY).and_raise(Errno::EACCES)

      expect(described_class.isolate_operation?).to be(false)
    end

    it "does not trust a worker's filename as evidence of sandboxing" do
      program_name = $PROGRAM_NAME
      $PROGRAM_NAME = (HOMEBREW_LIBRARY_PATH/"sandbox_operation.rb").to_s
      allow(described_class).to receive(:use_for?).and_return(true)

      expect(described_class.isolate_operation?).to be(true)
    ensure
      $PROGRAM_NAME = program_name
    end

    it "checks the opt-out policy inside an external sandbox" do
      allow(described_class).to receive(:nested_sandbox?).and_return(true)
      expect(described_class).to receive(:use_for?).with("processing downloaded files")
                                                   .and_return(false)

      described_class.isolate_operation?
    end

    it "runs commands with a warning when the sandbox is unavailable" do
      allow(described_class).to receive(:available?).and_return(false)
      warnings = []
      allow(described_class).to receive(:opoo) { |message| warnings << message }

      expect([described_class.capture("/bin/echo", args: ["completed"]).stdout, warnings])
        .to eq(["completed\n", ["Sandbox unavailable: processing downloaded files without sandboxing!"]])
    end

    it "extracts archives with a warning when relying on an outer sandbox" do
      allow(described_class).to receive_messages(available?: true, avoid_nested_sandboxing?: true)
      directory = mktmpdir
      warnings = []
      allow(described_class).to receive(:opoo) { |message| warnings << message }
      UnpackStrategy::Tar.new(TEST_FIXTURE_DIR/"cask/container.tar.gz").extract(to: directory)

      expect([directory.children(false).map(&:to_s), warnings])
        .to eq([["container"],
                ["Processing downloaded files without Homebrew's sandbox; relying on the outer sandbox."]])
    end
  end

  describe "::for_operation" do
    it "allows reading its output directory" do
      directory = mktmpdir

      expect(described_class.for_operation(write_paths: [directory]).profile.rules)
        .to include(have_attributes(allow: true, operation: "file-read*",
                                    filter: have_attributes(path: directory.realpath.to_s)))
    end

    it "allows a prefix inside the repository while protecting Homebrew's code" do
      repository = mktmpdir
      stub_const("HOMEBREW_REPOSITORY", repository)
      stub_const("HOMEBREW_PREFIX", repository/".brew-padded")
      stub_const("HOMEBREW_LIBRARY", repository/"Library")
      stub_const("HOMEBREW_BREW_FILE", repository/"bin/brew")

      expect(described_class.for_operation(write_paths: [HOMEBREW_PREFIX]).profile.rules.filter_map do |rule|
        rule.filter&.path if !rule.allow && rule.operation == "file-write*"
      end).to contain_exactly((repository/"Library").to_s, (repository/".git").to_s, (repository/"bin/brew").to_s)
    end
  end

  describe "#capture" do
    before do
      allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
      allow(sandbox).to receive(:apply_before_exec?).and_return(false)
    end

    it "captures binary output without a terminal, including from a worker thread" do
      result = Thread.new do
        sandbox.capture(RbConfig.ruby, args: ["-e", 'STDOUT.write "a\\x00b\\n"'])
      end.value

      expect(result.stdout).to eq("a\x00b\n")
    end

    it "passes sandbox inheritance to children through a descriptor, not the environment" do
      [false, true].each do |apply_before_exec|
        allow(sandbox).to receive(:apply_before_exec?).and_return(apply_before_exec)
        allow(sandbox).to receive(:apply!)
        result = sandbox.capture(RbConfig.ruby, args: ["-e", <<~RUBY, HOMEBREW_LIBRARY_PATH/"sandbox.rb"])
          abort "Environment marker was passed" if ENV.key?("HOMEBREW_SANDBOX")
          abort "Descriptor was not passed" unless File.identical?(IO.new(198, autoclose: false), ARGV.fetch(0))
          system(RbConfig.ruby, "-e", 'exit File.identical?(IO.new(198, autoclose: false), ARGV.fetch(0))', ARGV.fetch(0)) || abort
        RUBY

        expect(result).to be_success
      end
    end

    it "gives commands a private home and temporary directory without inherited secrets" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "secret"
      result = sandbox.capture(RbConfig.ruby, args: ["-rjson", "-e", <<~RUBY])
        puts JSON.generate([
          ENV["HOMEBREW_GITHUB_API_TOKEN"],
          ENV.fetch("HOME") == ENV.fetch("TMPDIR"),
          ENV.fetch("TEMP") == ENV.fetch("TMPDIR"),
          ENV.fetch("TMP") == ENV.fetch("TMPDIR"),
          File.stat(ENV.fetch("TMPDIR")).mode & 0777,
        ])
      RUBY

      expect(JSON.parse(result.stdout)).to eq([nil, true, true, true, 0700])
    end

    it "does not grant write access to the shared cache or temporary directory" do
      sandbox.capture(RbConfig.ruby, args: ["-e", "exit"])

      expect(sandbox.profile.rules.filter_map { |rule| rule.filter&.path if rule.allow }).not_to include(
        HOMEBREW_CACHE.to_s, HOMEBREW_TEMP.to_s
      )
    end

    it "preserves an explicitly supplied home and authentication environment" do
      ENV["SSH_AUTH_SOCK"] = (mktmpdir/"agent.sock").to_s
      env = { "HOME" => Dir.home(ENV.fetch("USER")), "SSH_AUTH_SOCK" => ENV.fetch("SSH_AUTH_SOCK") }
      result = sandbox.capture(RbConfig.ruby, env:, args: ["-rjson", "-e", <<~RUBY])
        puts JSON.generate(ENV.values_at("HOME", "SSH_AUTH_SOCK"))
      RUBY

      expect(JSON.parse(result.stdout)).to eq([Dir.home(ENV.fetch("USER")), ENV.fetch("SSH_AUTH_SOCK")])
    end

    it "preserves the working directory for relative command arguments" do
      directory = mktmpdir
      (directory/"input").write("content")
      result = directory.cd { sandbox.capture("cat", args: ["input"]) }

      expect(result.stdout).to eq("content")
    end

    it "drains command output while supplying a large input" do
      input = "x" * 1_000_000
      result = Timeout.timeout(5) do
        sandbox.capture(RbConfig.ruby, input:, args: ["-e", <<~RUBY])
          $stdout.sync = true
          while (chunk = $stdin.read(4096))
            $stdout.write(chunk)
          end
        RUBY
      end

      expect(result.stdout).to eq(input)
    end

    it "reports a sandbox setup failure without executing the command" do
      allow(sandbox).to receive(:apply_before_exec?).and_return(true)
      allow(sandbox).to receive(:apply!).and_raise("Sandbox setup failed")
      result = sandbox.capture("echo", args: ["executed"], must_succeed: false, print_stderr: false)

      expect([result.exit_status, result.stdout, result.stderr]).to eq([127, "", "Sandbox setup failed\n"])
    end

    it "captures setup warnings when the caller redirects standard error" do
      allow(sandbox).to receive(:apply_before_exec?).and_return(true)
      allow(sandbox).to receive(:apply!) { warn "Sandbox warning" }

      expect { sandbox.capture("true") }.to output("Sandbox warning\n").to_stderr
    end

    it "interrupts helpers even after they close their output pipes" do
      directory = mktmpdir
      helper_pid = directory/"pid"
      result = directory/"result"
      caller = Thread.current
      interrupter = Thread.new do
        Timeout.timeout(10) { sleep 0.01 until helper_pid.exist? && helper_pid.size? }
        caller.raise Interrupt
      end

      expect do
        sandbox.capture(RbConfig.ruby, args: ["-e", <<~RUBY, helper_pid, result])
          trap("INT") { exit! }
          fork do
            STDOUT.reopen(File::NULL, "w")
            STDERR.reopen(File::NULL, "w")
            trap("INT") do
              File.write(ARGV.fetch(1), "interrupted")
              exit!
            end
            File.write(ARGV.fetch(0), Process.pid)
            sleep 5
            File.write(ARGV.fetch(1), "survived cancellation")
          end
          Process.wait
        RUBY
      end.to raise_error(Interrupt)

      Timeout.timeout(10) { sleep 0.01 until result.exist? && result.size? }
      expect(result.read).to eq("interrupted")
    ensure
      interrupter&.kill
      if helper_pid&.exist? && (pid = helper_pid.read.to_i).positive?
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end
  end

  describe "#capture confinement" do
    before do
      skip "Sandbox unavailable." unless described_class.available?
      skip "Nested sandboxing is not supported." if described_class.nested_sandbox?
      allow(described_class).to receive(:isolate_operation?).and_call_original
    end

    it "allows its output directory and denies writes through an escaping symlink" do
      directory = mktmpdir
      output = directory/"output"
      output.mkpath
      (output/"escape").make_symlink(directory/"outside")
      sandbox = described_class.for_operation(read_paths: [directory], write_paths: [output])
      sandbox.capture(RbConfig.ruby, args: ["-e", <<~RUBY, output])
        File.write(File.join(ARGV.fetch(0), "allowed"), "written")
        begin
          File.write(File.join(ARGV.fetch(0), "escape"), "escaped")
          abort "Write escaped the sandbox"
        rescue Errno::EPERM, Errno::EACCES
          nil
        end
      RUBY

      expect((output/"allowed").read).to eq("written")
    end

    it "extracts a disk image in the sandbox", :needs_macos do
      directory = mktmpdir
      UnpackStrategy::Dmg.new(TEST_FIXTURE_DIR/"cask/container.dmg").extract_nestedly(to: directory)

      expect(directory.children(false).map(&:to_s)).to eq(["container"])
    end
  end

  describe "::use_for?" do
    before do
      ENV.delete("HOMEBREW_SANDBOX")
    end

    it "quietly inherits a Homebrew sandbox after probing its write protection" do
      allow(IO).to receive(:new).with(198, autoclose: false).and_return($stdin)
      allow(File).to receive(:identical?).with($stdin, (HOMEBREW_LIBRARY_PATH/"sandbox.rb").to_s).and_return(true)
      allow(described_class).to receive_messages(available?: true, avoid_nested_sandboxing?: true)
      allow(File).to receive(:open).with(HOMEBREW_BREW_FILE, File::WRONLY).and_raise(Errno::EPERM)
      warnings = []
      allow(described_class).to receive(:opoo) { |message| warnings << message }

      expect([described_class.use_for?("running post-install"), warnings]).to eq([false, []])
    end

    it "rejects an inherited descriptor without enforced write protection" do
      allow(IO).to receive(:new).with(198, autoclose: false).and_return($stdin)
      allow(File).to receive(:identical?).with($stdin, (HOMEBREW_LIBRARY_PATH/"sandbox.rb").to_s).and_return(true)
      allow(described_class).to receive_messages(available?: true, avoid_nested_sandboxing?: true)
      brew_file = mktmpdir/"brew"
      brew_file.write("unchanged")
      stub_const("HOMEBREW_BREW_FILE", brew_file)

      expect { described_class.use_for?("building") }.to raise_error(/Inherited sandbox permits writes/)
    end

    it "uses an available non-nested sandbox" do
      allow(described_class).to receive_messages(available?: true, avoid_nested_sandboxing?: false)

      expect(described_class.use_for?("running install hooks")).to be(true)
    end

    it "warns when the sandbox is unavailable" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(described_class).to receive(:opoo).with("Sandbox unavailable: running install hooks without sandboxing!")

      expect(described_class.use_for?("running install hooks")).to be(false)
    end

    it "warns once per process when the sandbox is unavailable" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(described_class).to receive(:opoo)
        .with("Sandbox unavailable: running install hooks without sandboxing!").once

      2.times { described_class.use_for?("running install hooks") }
    end

    it "can quietly fall back when the sandbox is unavailable" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(described_class).not_to receive(:opoo)

      expect(described_class.use_for?("testing a formula", warn_without_sandbox: false)).to be(false)
    end

    it "warns when relying on an outer sandbox" do
      allow(described_class).to receive_messages(available?: true, avoid_nested_sandboxing?: true)
      expect(described_class).to receive(:opoo)
        .with("Running install hooks without Homebrew's sandbox; relying on the outer sandbox.")

      expect(described_class.use_for?("running install hooks")).to be(false)
    end
  end

  describe "::run_or_fork" do
    let(:command_sandbox) { instance_double(described_class) }

    it "configures and uses the sandbox when available" do
      allow(described_class).to receive_messages(new: command_sandbox, use_for?: true)
      expect(command_sandbox).to receive(:run).with("command", "argument", retain_tmp: true, debug: true)

      described_class.run_or_fork("command", "argument", step: "running a command",
                                 retain_tmp: true, debug: true) do |configured|
        expect(configured).to eq(command_sandbox)
      end
    end

    it "forks without configuring a sandbox when unavailable" do
      allow(described_class).to receive(:use_for?).and_return(false)
      expect(described_class).not_to receive(:new)
      expect(Utils).to receive(:safe_fork)

      described_class.run_or_fork("command", step: "running a command") do
        raise "sandbox should not be configured"
      end
    end
  end

  describe "#run temporary directory" do
    before do
      stub_const("HOMEBREW_TEMP", HOMEBREW_TEMP/"sandbox")
      HOMEBREW_TEMP.mkpath
      allow(described_class).to receive(:terminal_ioctl_request).and_return(0)
      allow(PTY).to receive(:open).and_wrap_original do |original, &block|
        original.call do |controller, worker|
          allow(worker).to receive(:ioctl).with(0, 0)
          block.call(controller, worker)
        end
      end
      allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
      allow(sandbox).to receive(:ensure_child_tty_available)
      allow(sandbox).to receive(:apply!)
      allow(sandbox).to receive(:record_sandbox_log)
    end

    it "gives the child a private writable socket directory and removes it afterwards" do
      sandbox.allow_write_system_temp
      sandbox.deny_all_network
      expect(sandbox).to receive(:sandbox_command) do |args, tmpdir|
        expect(sandbox.profile.rules.select { |rule| rule.allow && rule.operation == "network*" }
          .map { |rule| [rule.filter&.path, rule.filter&.type] }).to eq([[tmpdir, :subpath]])
        args
      end
      expect do
        sandbox.run RbConfig.ruby, "-e", <<~RUBY, HOMEBREW_TEMP
          temporary = ENV.fetch("HOMEBREW_TEMP")
          abort "Shared temporary directory" unless File.dirname(temporary) == ARGV.fetch(0)
          abort "Unexpected permissions" unless File.stat(temporary).mode & 0777 == 0700
          abort "Inconsistent environment" unless %w[TMPDIR TEMP TMP].all? { |key| ENV[key] == temporary }
          File.write(File.join(temporary, "child-file"), "written")
        RUBY
      end.not_to raise_error
      expect(sandbox.profile.rules).to include(have_attributes(allow: false, operation: "network*", filter: nil))
      expect(HOMEBREW_TEMP.children).to be_empty
    end

    it "retains temporary files when requested" do
      sandbox.run RbConfig.ruby, "-e", "exit", retain_tmp: true

      expect(HOMEBREW_TEMP.children.length).to eq(1)
    end

    it "retains temporary files on failure when debugging" do
      expect { sandbox.run RbConfig.ruby, "-e", "exit 1", debug: true }.to raise_error(ErrorDuringExecution)
      expect(HOMEBREW_TEMP.children.length).to eq(1)
    end

    it "retains temporary files on interruption when debugging" do
      allow(sandbox).to receive(:sandbox_command).and_raise(Interrupt)

      expect { sandbox.run "command", debug: true }.to raise_error(Interrupt)
      expect(HOMEBREW_TEMP.children.length).to eq(1)
    end

    it "does not retain temporary files for fatal exceptions when debugging" do
      allow(sandbox).to receive(:sandbox_command).and_raise(NoMemoryError)

      expect { sandbox.run "command", debug: true }.to raise_error(NoMemoryError)
      expect(HOMEBREW_TEMP.children).to be_empty
    end
  end

  describe "::with_preserved_brew_file" do
    it "restores bin/brew after a sandboxed process replaces it" do
      prefix = mktmpdir
      stub_const("HOMEBREW_PREFIX", prefix)
      brew_file = prefix/"bin/brew"
      original_brew_file = prefix/"Homebrew/bin/brew"
      original_brew_file.dirname.mkpath
      original_brew_file.write "#!/bin/sh\n"
      brew_file.dirname.mkpath
      brew_file.make_relative_symlink original_brew_file
      original_target = brew_file.readlink
      original_directory_mode = brew_file.dirname.stat.mode & 07777
      allow(described_class).to receive(:full_write_isolation?).and_return(false)

      described_class.with_preserved_brew_file do
        FileUtils.rm_f brew_file
        brew_file.write "malicious\n"
        brew_file.dirname.chmod 0500
      end

      expect(brew_file).to be_a_symlink
      expect(brew_file.readlink).to eq(original_target)
      expect(brew_file.dirname.stat.mode & 07777).to eq(original_directory_mode)
    end
  end

  describe "#add_install_hook_rules" do
    it "applies common install hook restrictions" do
      expect(sandbox).to receive(:allow_write_temp_and_cache).ordered
      expect(sandbox).to receive(:deny_write_homebrew_repository).ordered
      expect(sandbox).to receive(:deny_read_home).ordered
      expect(sandbox).to receive(:deny_all_network).ordered

      sandbox.add_install_hook_rules(network_access_allowed: false)
    end

    it "allows network access when requested" do
      allow(sandbox).to receive_messages(
        allow_write_temp_and_cache:     nil,
        deny_write_homebrew_repository: nil,
        deny_read_home:                 nil,
      )
      expect(sandbox).not_to receive(:deny_all_network)

      sandbox.add_install_hook_rules(network_access_allowed: true)
    end
  end

  describe "::run_command" do
    let(:command_sandbox) { instance_double(described_class) }
    let(:writable_path) { mktmpdir }

    before do
      allow(described_class).to receive_messages(
        available?: true,
        new:        command_sandbox,
      )
      allow(command_sandbox).to receive_messages(
        allow_write_temp_and_cache: nil,
        allow_write_path:           nil,
        deny_read_home:             nil,
        deny_all_network:           nil,
        run:                        nil,
      )
    end

    it "runs a command with the requested writable path" do
      expect(command_sandbox).to receive(:allow_write_temp_and_cache).ordered
      expect(command_sandbox).to receive(:allow_write_path).with(writable_path.realpath).ordered
      expect(command_sandbox).to receive(:deny_read_home).ordered
      expect(command_sandbox).not_to receive(:deny_all_network)
      expect(command_sandbox).to receive(:run).with(
        "/bin/sh",
        "-c",
        "cd \"$1\" && shift && exec \"$@\"",
        "brew-sandbox-exec",
        writable_path.realpath,
        "make",
        "test",
      ).ordered

      described_class.run_command("make", "test", writable_path:)
    end

    it "can deny network access" do
      expect(command_sandbox).to receive(:deny_all_network)

      described_class.run_command("make", writable_path:, deny_network: true)
    end

    it "does not run unsandboxed when sandboxing is unavailable" do
      allow(described_class).to receive_messages(available?: false, failure_reason: "sandbox unavailable")
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path:) }
        .to raise_error(RuntimeError, "sandbox unavailable")
    end

    it "raises a usage error when the writable path does not exist" do
      missing_path = writable_path/"missing"
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path: missing_path) }
        .to raise_error(UsageError, "Invalid usage: `#{missing_path}` is not a writable directory.")
    end

    it "raises a usage error when the writable path is not a directory" do
      file_path = writable_path/"file"
      FileUtils.touch file_path
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path: file_path) }
        .to raise_error(UsageError, "Invalid usage: `#{file_path}` is not a writable directory.")
    end
  end

  describe "#copy_pty_output" do
    it "treats a PTY EIO as EOF" do
      controller = instance_double(IO)
      allow(controller).to receive(:each_char).and_raise(Errno::EIO)

      expect { sandbox.copy_pty_output(controller) }.not_to raise_error
    end
  end

  describe "::failure_reason" do
    let(:sandbox_class) { Class.new(described_class) }

    it "returns nil if the sandbox is available" do
      allow(sandbox_class).to receive(:state).and_return(:available)

      expect(sandbox_class.failure_reason).to be_nil
    end

    it "returns a sandbox failure reason if the sandbox is unavailable" do
      allow(sandbox_class).to receive(:state).and_return(:unavailable)

      expect(sandbox_class.failure_reason).to match(/sandbox/i)
    end
  end

  describe "::executable" do
    let(:sandbox_class) do
      Class.new(Sandbox) do
        class << self
          attr_accessor :test_executable_name, :unsuitable_executables

          def executable_name = test_executable_name

          def executable_usable?(candidate)
            unsuitable_executables.exclude?(candidate)
          end
        end
      end
    end
    let(:first_dir) { mktmpdir }
    let(:second_dir) { mktmpdir }
    let(:homebrew_bin) { mktmpdir }
    let(:executable_name) { "sandbox-tool" }
    let(:first_executable) { first_dir/executable_name }
    let(:second_executable) { second_dir/executable_name }
    let(:homebrew_executable) { homebrew_bin/executable_name }

    before do
      sandbox_class.test_executable_name = executable_name
      sandbox_class.unsuitable_executables = []
      stub_const("HOMEBREW_BREW_FILE", homebrew_bin/"brew")
    end

    it "uses the first suitable executable candidate" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      FileUtils.touch second_executable
      FileUtils.chmod "+x", second_executable
      stub_const("ORIGINAL_PATHS", [first_dir])

      with_env(PATH: second_dir.to_s) do
        expect(sandbox_class.executable).to eq(first_executable)
      end
    end

    it "skips unsuitable executable candidates" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      FileUtils.touch second_executable
      FileUtils.chmod "+x", second_executable
      stub_const("ORIGINAL_PATHS", [first_dir])
      sandbox_class.unsuitable_executables = [first_executable]

      with_env(PATH: second_dir.to_s) do
        expect(sandbox_class.executable).to eq(second_executable)
      end
    end

    it "falls back to the original Homebrew bin directory" do
      FileUtils.touch homebrew_executable
      FileUtils.chmod "+x", homebrew_executable
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect(sandbox_class.executable).to eq(homebrew_executable)
      end
    end

    it "checks absolute executable paths directly" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      sandbox_class.test_executable_name = first_executable.to_s
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect(sandbox_class.executable).to eq(first_executable)
      end
    end

    it "raises when no executable candidate exists" do
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect { sandbox_class.executable! }
          .to raise_error(RuntimeError, "#{executable_name} is required to use the sandbox.")
      end
    end
  end

  describe "#path_filter" do
    # The OS-specific renderer quotes paths safely, so no character is rejected.
    test_each(["'", '"', "(", ")", "\\", " ", ";", "#", "\n"]) do |char|
      it "allows paths containing #{char.inspect}" do
        expect { sandbox.path_filter(mktmpdir/"foo#{char}bar", :subpath) }.not_to raise_error
      end
    end
  end

  describe "#allow_read_if_exists" do
    it "allows reads for existing paths" do
      file = mktmpdir/"foo.rb"
      FileUtils.touch file

      sandbox.allow_read_if_exists path: file

      rule = sandbox.profile.rules.fetch(-1)
      expect(rule).to have_attributes(allow: true, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: file.realpath.to_s, type: :literal)
    end

    it "skips missing paths" do
      sandbox.allow_read_if_exists path: mktmpdir/"missing.rb"

      expect(sandbox.profile.rules).to be_empty
    end

    it "skips nil paths" do
      sandbox.allow_read_if_exists path: nil

      expect(sandbox.profile.rules).to be_empty
    end
  end

  describe "#allow_process_exec" do
    it "allows a process to run outside the sandbox when requested" do
      sandbox.allow_process_exec "/usr/bin/sudo", no_sandbox: true

      rule = sandbox.profile.rules.fetch(-1)
      expect(rule).to have_attributes(allow: true, operation: "process-exec", modifier: "no-sandbox")
      expect(rule.filter).to have_attributes(path: "/usr/bin/sudo", type: :literal)
    end
  end

  describe "#deny_read_path" do
    it "denies reads for a subpath" do
      dir = mktmpdir/"foo"
      dir.mkpath

      sandbox.deny_read_path dir

      rule = sandbox.profile.rules.fetch(-1)
      expect(rule).to have_attributes(allow: false, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: dir.realpath.to_s, type: :subpath)
    end
  end

  describe "#deny_read_home" do
    let(:home) { mktmpdir/"home" }
    let(:prefix) { mktmpdir/"prefix" }
    let(:repository) { mktmpdir/"repository" }
    let(:temp) { mktmpdir/"tmp" }
    let(:cache) { mktmpdir/"cache" }
    let(:logs) { mktmpdir/"logs" }

    before do
      [home, prefix, repository, temp, cache, logs].each(&:mkpath)
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home.to_s)
      stub_const("HOMEBREW_PREFIX", prefix)
      stub_const("HOMEBREW_REPOSITORY", repository)
      stub_const("HOMEBREW_TEMP", temp)
      stub_const("HOMEBREW_CACHE", cache)
      stub_const("HOMEBREW_LOGS", logs)
    end

    it "denies reads from the real home" do
      sandbox.deny_read_home

      rule = sandbox.profile.rules.fetch(-1)
      expect(rule).to have_attributes(allow: false, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: home.realpath.to_s, type: :subpath)
    end

    test_each([
      [:HOMEBREW_PREFIX, "prefix"],
      [:HOMEBREW_REPOSITORY, "repository"],
      [:HOMEBREW_CACHE, "cache"],
      [:HOMEBREW_TEMP, "tmp"],
      [:HOMEBREW_LOGS, "Library/Logs/Homebrew"],
    ]) do |(constant, directory)|
      it "skips the deny when #{constant} is inside the real home" do
        stub_const(constant.to_s, home/directory)
        # The constant under test is chosen dynamically per example.
        # rubocop:disable Sorbet/ConstantsFromStrings
        Object.const_get(constant).mkpath
        # rubocop:enable Sorbet/ConstantsFromStrings

        sandbox.deny_read_home

        expect(sandbox.profile.rules).to be_empty
      end
    end

    test_each([
      ["GITHUB_WORKSPACE", "workspace"],
      ["RUNNER_WORKSPACE", "runner-workspace"],
      ["RUNNER_TEMP", "runner-temp"],
    ]) do |(env, directory)|
      it "skips the deny when #{env} is inside the real home" do
        (home/directory).mkpath

        with_env(env => (home/directory).to_s) do
          sandbox.deny_read_home
        end

        expect(sandbox.profile.rules).to be_empty
      end
    end

    it "skips the deny when a runner path resolves inside the real home" do
      (home/"workspace").mkpath
      workspace_link = mktmpdir/"workspace"
      FileUtils.ln_s home/"workspace", workspace_link

      with_env(GITHUB_WORKSPACE: workspace_link.to_s) do
        sandbox.deny_read_home
      end

      expect(sandbox.profile.rules).to be_empty
    end

    it "denies known sensitive home paths when Homebrew needs home access" do
      cache = home/"Library/Caches/Homebrew"
      stub_const("HOMEBREW_CACHE", cache)
      allowed_dirs = [
        cache,
        home/"Library/Preferences",
        home/".config",
        home/".config/homebrew",
        home/"src",
      ]
      sensitive_dirs = [
        home/".claude",
        home/".config/gcloud",
        home/".config/gh",
        home/".config/fish",
        home/".config/huggingface",
        home/".config/pip",
        home/".config/pypoetry",
        home/".config/rclone",
        home/".kiro",
        home/".pip",
        home/".ssh",
        home/"Documents",
      ]
      sensitive_files = [
        home/".bash_login",
        home/".bash_logout",
        home/".bash_profile",
        home/".bashrc",
        home/".bash_history",
        home/".cache/huggingface/token",
        home/".claude.json",
        home/".config/composer/auth.json",
        home/".config/containers/auth.json",
        home/".config/sops/age/keys.txt",
        home/".cargo/credentials.toml",
        home/".gem/credentials",
        home/".git-credentials",
        home/".mysql_history",
        home/".netrc",
        home/".npmrc",
        home/".profile",
        home/".psql_history",
        home/".pypirc",
        home/".python_history",
        home/".terraform.d/credentials.tfrc.json",
        home/".zlogin",
        home/".zlogout",
        home/".zprofile",
        home/".zshenv",
        home/".zshrc",
        home/".zsh_history",
      ]

      [*allowed_dirs, *sensitive_dirs].each(&:mkpath)
      sensitive_files.each do |path|
        path.dirname.mkpath
        FileUtils.touch path
      end

      sandbox.deny_read_home

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).to include(*(sensitive_dirs + sensitive_files).map { |path| path.realpath.to_s })
      expect(denied).not_to include(*allowed_dirs.map { |path| path.realpath.to_s })
    end

    it "keeps Homebrew readable inside a sensitive home path" do
      stub_const("HOMEBREW_PREFIX", home/"Documents/homebrew")
      [HOMEBREW_PREFIX, home/".ssh"].each(&:mkpath)

      sandbox.deny_read_home

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).to contain_exactly((home/".ssh").realpath.to_s)
    end

    it "warns when Homebrew is inside a sensitive home path" do
      stub_const("HOMEBREW_PREFIX", home/"Documents/homebrew")
      HOMEBREW_PREFIX.mkpath

      expect(sandbox).to receive(:opoo).with(<<~EOS)
        The sandbox cannot prevent formulae from reading:
          #{(home/"Documents").realpath}
        because this required path is inside it:
          #{HOMEBREW_PREFIX.realpath}
        Formulae may access personal data in this directory.
      EOS

      sandbox.deny_read_home
    end

    it "does not deny arbitrary home entries whose names contain parentheses or backslashes" do
      stub_const("HOMEBREW_LOGS", home/"Library/Logs/Homebrew")
      teams_log = home/"Library/Logs/Microsoft Teams Helper (Renderer)"
      backslash_dir = home/"I:\\"
      [home/"Library/Logs/Homebrew", teams_log, backslash_dir, home/".ssh"].each(&:mkpath)

      sandbox.deny_read_home

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include(teams_log.realpath.to_s, backslash_dir.realpath.to_s)
    end

    it "does not deny sensitive symlinks that resolve outside home" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      HOMEBREW_CACHE.mkpath
      FileUtils.ln_s File::NULL, home/".mysql_history"

      sandbox.deny_read_home

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).not_to include(File::NULL)
    end

    it "passes resolved sensitive paths to deny_read_path" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      HOMEBREW_CACHE.mkpath
      target = home/"history"
      FileUtils.touch target
      FileUtils.ln_s target, home/".mysql_history"

      expect(sandbox).to receive(:deny_read_path).with(target.realpath)

      sandbox.deny_read_home
    end

    it "ignores broken sensitive symlinks" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      HOMEBREW_CACHE.mkpath
      FileUtils.ln_s home/"missing", home/".mysql_history"

      expect { sandbox.deny_read_home }.not_to raise_error
    end

    it "keeps the trust store readable so sandboxed builds can re-check tap trust" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      config_home = home/".homebrew"
      [home/"Library/Caches/Homebrew", config_home, home/".ssh"].each(&:mkpath)
      trust_file = config_home/"trust.json"
      FileUtils.touch trust_file

      with_env(HOMEBREW_USER_CONFIG_HOME: config_home.to_s) do
        sandbox.deny_read_home
      end

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include(trust_file.realpath.to_s)
    end

    it "keeps the XDG trust store readable so sandboxed builds can re-check tap trust" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      config_home = home/".config/homebrew"
      gh_config = home/".config/gh"
      [home/"Library/Caches/Homebrew", config_home, gh_config, home/".ssh"].each(&:mkpath)
      trust_file = config_home/"trust.json"
      FileUtils.touch trust_file

      with_env(HOMEBREW_USER_CONFIG_HOME: config_home.to_s) do
        sandbox.deny_read_home
      end

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).to include(gh_config.realpath.to_s)
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include((home/".config").realpath.to_s)
      expect(denied).not_to include(trust_file.realpath.to_s)
    end

    it "keeps the Xcode directories readable so builds can use them", :needs_macos do
      developer = home/"Library/Developer"
      swiftpm = home/"Library/Caches/org.swift.swiftpm"
      [developer, swiftpm, home/".ssh"].each(&:mkpath)

      sandbox.deny_read_home

      denied = sandbox.profile.rules.map { |rule| rule.filter&.path }
      expect(denied).not_to include(developer.realpath.to_s, swiftpm.realpath.to_s)
      expect(denied).to include((home/".ssh").realpath.to_s)
    end
  end

  describe "#allow_write_path_if_exists" do
    it "allows writes for existing paths" do
      dir = mktmpdir/"foo"
      dir.mkpath

      sandbox.allow_write_path_if_exists dir

      rule = sandbox.profile.rules.fetch(0)
      expect(rule).to have_attributes(allow: true, operation: "file-write*")
      expect(rule.filter).to have_attributes(path: dir.realpath.to_s, type: :subpath)
    end

    it "skips missing paths" do
      sandbox.allow_write_path_if_exists mktmpdir/"missing"

      expect(sandbox.profile.rules).to be_empty
    end

    it "skips nil paths" do
      sandbox.allow_write_path_if_exists nil

      expect(sandbox.profile.rules).to be_empty
    end
  end
end
