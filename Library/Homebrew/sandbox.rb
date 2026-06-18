# typed: strict
# frozen_string_literal: true

require "io/console"
require "pty"
require "tempfile"
require "exceptions"
require "utils/fork"
require "utils/output"

# Helper class for running a sub-process inside of a sandboxed environment.
class Sandbox
  include Utils::Output::Mixin

  class SandboxPathFilter
    sig { returns(String) }
    attr_reader :path

    sig { returns(Symbol) }
    attr_reader :type

    sig { params(path: String, type: Symbol).void }
    def initialize(path:, type:)
      @path = T.let(path.freeze, String)
      @type = type
    end
  end
  private_constant :SandboxPathFilter

  class SandboxRule
    sig { returns(T::Boolean) }
    attr_reader :allow

    sig { returns(String) }
    attr_reader :operation

    sig { returns(T.nilable(SandboxPathFilter)) }
    attr_reader :filter

    sig { returns(T.nilable(String)) }
    attr_reader :modifier

    sig {
      params(allow: T::Boolean, operation: String, filter: T.nilable(SandboxPathFilter),
             modifier: T.nilable(String)).void
    }
    def initialize(allow:, operation:, filter:, modifier:)
      @allow = allow
      @operation = operation
      @filter = filter
      @modifier = modifier
    end
  end
  private_constant :SandboxRule

  # Configuration profile for a sandbox.
  class SandboxProfile
    sig { returns(T::Array[SandboxRule]) }
    attr_reader :rules

    sig { void }
    def initialize
      @rules = T.let([], T::Array[SandboxRule])
    end

    sig { params(rule: SandboxRule).void }
    def add_rule(rule)
      @rules << rule
    end
  end
  private_constant :SandboxProfile

  sig { returns(T::Boolean) }
  def self.available?
    false
  end

  sig { params(install_from_tests: T::Boolean).void }
  def self.ensure_sandbox_installed!(install_from_tests: false); end

  sig { returns(Symbol) }
  def self.state
    available? ? :available : :unavailable
  end

  sig { returns(T.nilable(String)) }
  def self.failure_reason
    return if state == :available

    "The sandbox is not available."
  end

  sig { void }
  def self.reset_state!; end

  sig { returns(T::Array[String]) }
  def self.configuration_commands = []

  sig { returns(T::Array[String]) }
  def self.configuration_command_messages = []

  sig { returns(T.nilable(String)) }
  def self.sandbox_install_command = nil

  sig { void }
  def self.configure!
    ensure_sandbox_installed!
    reset_state!
  end

  sig { params(command: T.any(String, Pathname), writable_path: T.any(String, Pathname), deny_network: T::Boolean).void }
  def self.run_command(*command, writable_path:, deny_network: false)
    ensure_sandbox_installed!
    raise failure_reason || "The sandbox is not available." unless available?

    writable_path = Pathname(writable_path).expand_path
    if !writable_path.directory? || !writable_path.writable?
      raise UsageError,
            "`#{writable_path}` is not a writable directory."
    end

    writable_path = writable_path.realpath
    sandbox = new
    sandbox.allow_write_temp_and_cache
    sandbox.allow_write_path writable_path
    sandbox.deny_read_home
    sandbox.deny_all_network if deny_network
    sandbox.run "/bin/sh", "-c", "cd \"$1\" && shift && exec \"$@\"", "brew-sandbox-exec", writable_path, *command
  end

  sig { returns(String) }
  def self.executable_name
    raise NotImplementedError, "Sandbox is not implemented for this OS."
  end

  sig { returns(::PATH) }
  def self.executable_candidate_paths
    executable_path = Pathname.new(executable_name)
    return PATH.new(executable_path.dirname) if executable_path.absolute?

    PATH.new(ORIGINAL_PATHS, ENV.fetch("PATH"), HOMEBREW_ORIGINAL_BREW_FILE.dirname)
  end

  sig { returns(T.nilable(Pathname)) }
  def self.executable
    executable_candidate_paths.each do |path|
      begin
        candidate = Pathname.new(File.expand_path(executable_name, path))
      rescue ArgumentError
        next
      end

      next if !candidate.file? || !candidate.executable?
      next unless executable_usable?(candidate)

      return candidate
    end

    nil
  end

  sig { returns(Pathname) }
  def self.executable!
    executable || raise("#{executable_name} is required to use the sandbox.")
  end

  sig { params(_candidate: Pathname).returns(T::Boolean) }
  def self.executable_usable?(_candidate)
    true
  end

  sig { returns(Integer) }
  def self.terminal_ioctl_request
    raise NotImplementedError, "Sandbox is not implemented for this OS."
  end

  sig { void }
  def initialize
    @profile = T.let(SandboxProfile.new, SandboxProfile)
    @failed = T.let(false, T::Boolean)
    @logfile = T.let(nil, T.nilable(T.any(String, Pathname)))
    @start = T.let(nil, T.nilable(Time))
  end

  sig { params(file: T.any(String, Pathname)).void }
  def record_log(file)
    @logfile = file
  end

  sig {
    params(allow: T::Boolean, operation: String, filter: T.nilable(SandboxPathFilter),
           modifier: T.nilable(String)).void
  }
  def add_rule(allow:, operation:, filter: nil, modifier: nil)
    rule = SandboxRule.new(allow:, operation:, filter:, modifier:)
    @profile.add_rule(rule)
  end

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def allow_read(path:, type: :literal)
    add_rule allow: true, operation: "file-read*", filter: path_filter(path, type)
  end

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def deny_read(path:, type: :literal)
    add_rule allow: false, operation: "file-read*", filter: path_filter(path, type)
  end

  sig { params(path: T.any(String, Pathname)).void }
  def deny_read_path(path)
    deny_read path:, type: :subpath
  end

  sig { void }
  def deny_read_home
    require "trust"

    home = Pathname(Dir.home(ENV.fetch("USER"))).realpath
    if [
      HOMEBREW_PREFIX,
      HOMEBREW_REPOSITORY,
      HOMEBREW_CACHE,
      HOMEBREW_LOGS,
      HOMEBREW_TEMP,
      ENV.fetch("GITHUB_WORKSPACE", nil),
      ENV.fetch("RUNNER_WORKSPACE", nil),
      ENV.fetch("RUNNER_TEMP", nil),
      Homebrew::Trust.trust_file,
      *home_write_paths.select { |path| File.exist?(path) },
    ].compact.any? do |path|
      path = Pathname(path)
      [path.expand_path, (path.realpath if path.exist?)].compact.any? { |pathname| pathname.ascend.include?(home) }
    end
      # When Homebrew or CI needs some `$HOME` paths to stay readable, deny only
      # well-known credential and personal-data paths instead of enumerating all
      # of `$HOME`.
      [
        ".ssh",
        ".aws",
        ".azure",
        ".boto",
        ".docker",
        ".config/fish",
        ".config/gh",
        ".config/gcloud",
        ".config/huggingface",
        ".config/pip",
        ".config/pypoetry",
        ".config/rclone",
        ".config/containers/auth.json",
        ".config/composer/auth.json",
        ".config/sops/age/keys.txt",
        ".gnupg",
        ".git-credentials",
        ".gitconfig",
        ".gsutil",
        ".kube",
        ".netrc",
        ".npmrc",
        ".yarnrc",
        ".yarnrc.yml",
        ".pnpmrc",
        ".bunfig.toml",
        ".pypirc",
        ".pip",
        ".poetry",
        ".local/share/pypoetry",
        ".gem/credentials",
        ".bundle/config",
        ".cargo/credentials",
        ".cargo/credentials.toml",
        ".composer/auth.json",
        ".condarc",
        ".m2/settings.xml",
        ".gradle/gradle.properties",
        ".sbt/1.0/credentials.sbt",
        ".terraform.d/credentials.tfrc.json",
        ".pulumi/credentials.json",
        ".oci/config",
        ".huggingface/token",
        ".cache/huggingface/token",
        ".claude",
        ".claude.json",
        ".kiro",
        ".bash_login",
        ".bash_logout",
        ".bash_profile",
        ".bashrc",
        ".bash_history",
        ".profile",
        ".zlogin",
        ".zlogout",
        ".zprofile",
        ".zshenv",
        ".zshrc",
        ".zsh_history",
        ".python_history",
        ".mysql_history",
        ".psql_history",
        ".env",
        ".env.local",
        "Documents",
        "Movies",
        "Music",
        "Pictures",
        "Library/Keychains",
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Dropbox",
        "Google Drive",
        "OneDrive",
      ].each do |path|
        path = home/path
        deny_read_path path if path.exist?
      end
      return
    end

    deny_read_path home
  end

  sig { params(path: T.nilable(T.any(String, Pathname)), type: Symbol).void }
  def allow_read_if_exists(path:, type: :literal)
    return unless path
    return unless File.exist?(path)

    allow_read path:, type:
  end

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def allow_write(path:, type: :literal)
    add_rule allow: true, operation: "file-write*", filter: path_filter(path, type)
    add_rule allow: true, operation: "file-write-setugid", filter: path_filter(path, type)
    add_rule allow: true, operation: "file-write-mode", filter: path_filter(path, type)
  end

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def deny_write(path:, type: :literal)
    add_rule allow: false, operation: "file-write*", filter: path_filter(path, type)
  end

  sig { params(path: T.any(String, Pathname)).void }
  def allow_write_path(path)
    allow_write path:, type: :subpath
  end

  sig { params(path: T.nilable(T.any(String, Pathname))).void }
  def allow_write_path_if_exists(path)
    return unless path
    return unless File.exist?(path)

    allow_write_path path
  end

  sig { params(path: T.any(String, Pathname)).void }
  def deny_write_path(path)
    deny_write path:, type: :subpath
  end

  sig { void }
  def allow_write_temp_and_cache
    allow_write_path HOMEBREW_TEMP
    allow_write_path HOMEBREW_CACHE
  end

  sig { void }
  def allow_cvs
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.cvspass"
  end

  sig { void }
  def allow_fossil
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil"
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil-journal"
  end

  sig { params(formula: Formula).void }
  def allow_write_cellar(formula)
    allow_write_path formula.rack
    allow_write_path formula.etc
    allow_write_path formula.var
  end

  sig { void }
  def allow_write_xcode; end

  sig { params(formula: Formula).void }
  def allow_write_log(formula)
    allow_write_path formula.logs
  end

  sig { void }
  def deny_write_homebrew_repository
    deny_write path: HOMEBREW_ORIGINAL_BREW_FILE
    if HOMEBREW_PREFIX.to_s == HOMEBREW_REPOSITORY.to_s
      deny_write_path HOMEBREW_LIBRARY
      deny_write_path HOMEBREW_REPOSITORY/".git"
    else
      deny_write_path HOMEBREW_REPOSITORY
    end
  end

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def allow_network(path:, type: :literal)
    add_rule allow: true, operation: "network*", filter: path_filter(path, type)
  end

  sig { void }
  def deny_all_network
    add_rule allow: false, operation: "network*"
  end

  sig { params(args: T.any(String, Pathname)).void }
  def run(*args)
    Dir.mktmpdir("homebrew-sandbox", HOMEBREW_TEMP) do |tmpdir|
      allow_network path: File.join(tmpdir, "socket"), type: :literal if allow_network_for_error_pipe?
      @start = T.let(Time.now, T.nilable(Time))

      begin
        command = sandbox_command(args, tmpdir)
        # Start sandbox in a pseudoterminal to prevent access of the parent terminal.
        PTY.open do |controller, worker|
          # Set the PTY's window size to match the parent terminal.
          # Some formula tests are sensitive to the terminal size and fail if this is not set.
          winch = proc do |_sig|
            controller.winsize = if $stdout.tty?
              # We can only use IO#winsize if the IO object is a TTY.
              $stdout.winsize
            else
              # Otherwise, default to tput, if available.
              # This relies on ncurses rather than the system's ioctl.
              [Utils.popen_read("tput", "lines").to_i, Utils.popen_read("tput", "cols").to_i]
            end
          end

          write_to_pty = proc do
            # Don't hang if stdin is not able to be used - throw EIO instead.
            old_ttin = trap(:TTIN, "IGNORE")

            # Update the window size whenever the parent terminal's window size changes.
            old_winch = trap(:WINCH, &winch)
            winch.call(nil)

            stdin_thread = Thread.new do
              IO.copy_stream($stdin, controller)
            rescue Errno::EIO
              # stdin is unavailable - move on.
            end

            stdout_thread = Thread.new do
              controller.each_char { |c| print(c) }
            end

            Utils.safe_fork(directory: tmpdir, yield_parent: true) do |error_pipe|
              if error_pipe
                # Child side
                Process.setsid
                controller.close
                worker.ioctl(self.class.terminal_ioctl_request, 0) # Make this the controlling terminal.

                ensure_child_tty_available

                # Move into a non-denied directory before `exec` so subsequent
                # `getcwd(3)` calls (which walk every parent) never cross a
                # `deny_read_home` path inherited from the caller's CWD.
                Dir.chdir(tmpdir)

                worker.close_on_exec = true
                exec(*command, in: worker, out: worker, err: worker) # And map everything to the PTY.
              else
                # Parent side
                worker.close
              end
            end
          rescue ChildProcessError => e
            raise ErrorDuringExecution.new(command, status: e.status)
          ensure
            stdin_thread&.kill
            stdout_thread&.kill
            trap(:TTIN, old_ttin)
            trap(:WINCH, old_winch)
          end

          if $stdin.tty?
            # If stdin is a TTY, use io.raw to set stdin to a raw, passthrough
            # mode while we copy the input/output of the process spawned in the
            # PTY. After we've finished copying to/from the PTY process, io.raw
            # will restore the stdin TTY to its original state.
            begin
              # Ignore SIGTTOU as setting raw mode will hang if the process is in the background.
              old_ttou = trap(:TTOU, "IGNORE")
              $stdin.raw(&write_to_pty)
            ensure
              trap(:TTOU, old_ttou)
            end
          else
            write_to_pty.call
          end
        end
      rescue
        @failed = true
        raise
      ensure
        record_sandbox_log
      end
    end
  end

  # @api private
  sig { params(path: T.any(String, Pathname), type: Symbol).returns(SandboxPathFilter) }
  def path_filter(path, type)
    # Any character is allowed: the OS-specific renderer quotes paths safely
    # (the seatbelt renderer escapes the `"` and `\` string delimiters; the
    # Linux sandbox passes each path as a separate argument), so even paths
    # with spaces, parentheses, quotes, backslashes or newlines are expressible.
    filter_path = case type
    when :regex   then path.to_s
    when :subpath, :literal
      expand_realpath(Pathname.new(path)).to_s
    else raise ArgumentError, "Invalid path filter type: #{type}"
    end

    SandboxPathFilter.new(path: filter_path, type:)
  end

  private

  sig { returns(SandboxProfile) }
  attr_reader :profile

  sig { returns(T::Boolean) }
  attr_reader :failed

  sig { returns(T.nilable(T.any(String, Pathname))) }
  attr_reader :logfile

  sig { returns(T.nilable(Time)) }
  attr_reader :start

  # Home directories a build needs to write to, and so must also read;
  # overridden per-OS (e.g. the Xcode directories on macOS).
  sig { returns(T::Array[String]) }
  def home_write_paths = []

  sig { params(_args: T::Array[T.any(String, Pathname)], _tmpdir: String).returns(T::Array[T.any(String, Pathname)]) }
  def sandbox_command(_args, _tmpdir)
    raise NotImplementedError, "Sandbox is not implemented for this OS."
  end

  sig { returns(T::Boolean) }
  def allow_network_for_error_pipe?
    false
  end

  sig { void }
  def ensure_child_tty_available; end

  sig { void }
  def record_sandbox_log; end

  sig { params(path: Pathname).returns(Pathname) }
  def expand_realpath(path)
    raise unless path.absolute?

    path.exist? ? path.realpath : expand_realpath(path.parent)/path.basename
  end
end

require "extend/os/sandbox"
