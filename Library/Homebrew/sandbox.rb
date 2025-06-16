# typed: strict
# frozen_string_literal: true

require "erb"
require "io/console"
require "pty"
require "tempfile"
require "utils/fork"

# Helper class for running a sub-process inside of a sandboxed environment.
class Sandbox
  SANDBOX_EXEC = "/usr/bin/sandbox-exec"
  private_constant :SANDBOX_EXEC

  # This is defined in the macOS SDK but Ruby unfortunately does not expose it.
  # This value can be found by compiling a C program that prints TIOCSCTTY.
  # The value is different on Linux but that's not a problem as we only support macOS in this file.
  TIOCSCTTY = 0x20007461
  private_constant :TIOCSCTTY

  sig { returns(T::Boolean) }
  def self.available?
    false
  end

  sig { void }
  def initialize
    @profile = T.let(SandboxProfile.new, SandboxProfile)
    @failed = T.let(false, T::Boolean)
  end

  sig { params(file: T.any(String, Pathname)).void }
  def record_log(file)
    @logfile = T.let(file, T.nilable(T.any(String, Pathname)))
  end

  sig { params(allow: T::Boolean, operation: String, filter: T.nilable(String), modifier: T.nilable(String)).void }
  def add_rule(allow:, operation:, filter: nil, modifier: nil)
    rule = SandboxRule.new(allow:, operation:, filter:, modifier:)
    @profile.add_rule(rule)
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

  sig { params(path: T.any(String, Pathname)).void }
  def deny_write_path(path)
    deny_write path:, type: :subpath
  end

  sig { void }
  def allow_write_temp_and_cache
    allow_write_path "/private/tmp"
    allow_write_path "/private/var/tmp"
    allow_write path: "^/private/var/folders/[^/]+/[^/]+/[C,T]/", type: :regex
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

  # Xcode projects expect access to certain cache/archive dirs.
  sig { void }
  def allow_write_xcode
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/Library/Developer"
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/Library/Caches/org.swift.swiftpm"
  end

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

  sig { params(path: T.any(String, Pathname), type: Symbol).void }
  def deny_network(path:, type: :literal)
    add_rule allow: false, operation: "network*", filter: path_filter(path, type)
  end

  sig { void }
  def allow_all_network
    add_rule allow: true, operation: "network*"
  end

  sig { void }
  def deny_all_network
    add_rule allow: false, operation: "network*"
  end

  sig { params(args: T.any(String, Pathname)).void }
  def run(*args)
    Dir.mktmpdir("homebrew-sandbox", HOMEBREW_TEMP) do |tmpdir|
      allow_network path: File.join(tmpdir, "socket"), type: :literal # Make sure we have access to the error pipe.

      seatbelt = File.new(File.join(tmpdir, "homebrew.sb"), "wx")
      seatbelt.write(@profile.dump)
      seatbelt.close
      @start = T.let(Time.now, T.nilable(Time))

      begin
        command = [SANDBOX_EXEC, "-f", seatbelt.path, *args]
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
                worker.ioctl(TIOCSCTTY, 0) # Make this the controlling terminal.
                File.open("/dev/tty", Fcntl::O_WRONLY).close # Workaround for https://developer.apple.com/forums/thread/663632
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
        sleep 0.1 # wait for a bit to let syslog catch up the latest events.
        syslog_args = [
          "-F", "$((Time)(local)) $(Sender)[$(PID)]: $(Message)",
          "-k", "Time", "ge", @start.to_i.to_s,
          "-k", "Message", "S", "deny",
          "-k", "Sender", "kernel",
          "-o",
          "-k", "Time", "ge", @start.to_i.to_s,
          "-k", "Message", "S", "deny",
          "-k", "Sender", "sandboxd"
        ]
        logs = Utils.popen_read("syslog", *syslog_args)

        # These messages are confusing and non-fatal, so don't report them.
        logs = logs.lines.grep_v(/^.*Python\(\d+\) deny file-write.*pyc$/).join

        unless logs.empty?
          if @logfile
            File.open(@logfile, "w") do |log|
              log.write logs
              log.write "\nWe use time to filter sandbox log. Therefore, unrelated logs may be recorded.\n"
            end
          end

          if @failed && Homebrew::EnvConfig.verbose?
            ohai "Sandbox Log", logs
            $stdout.flush # without it, brew test-bot would fail to catch the log
          end
        end
      end
    end
  end

  # @api private
  sig { params(path: T.any(String, Pathname), type: Symbol).returns(String) }
  def path_filter(path, type)
    invalid_char = ['"', "'", "(", ")", "\n", "\\"].find do |c|
      path.to_s.include?(c)
    end
    raise ArgumentError, "Invalid character #{invalid_char} in path: #{path}" if invalid_char

    case type
    when :regex   then "regex #\"#{path}\""
    when :subpath then "subpath \"#{expand_realpath(Pathname.new(path))}\""
    when :literal then "literal \"#{expand_realpath(Pathname.new(path))}\""
    else raise ArgumentError, "Invalid path filter type: #{type}"
    end
  end

  private

  sig { params(path: Pathname).returns(Pathname) }
  def expand_realpath(path)
    raise unless path.absolute?

    path.exist? ? path.realpath : expand_realpath(path.parent)/path.basename
  end

  class SandboxRule
    sig { returns(T::Boolean) }
    attr_reader :allow

    sig { returns(String) }
    attr_reader :operation

    sig { returns(T.nilable(String)) }
    attr_reader :filter

    sig { returns(T.nilable(String)) }
    attr_reader :modifier

    sig { params(allow: T::Boolean, operation: String, filter: T.nilable(String), modifier: T.nilable(String)).void }
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
    SEATBELT_ERB = <<~ERB
      (version 1)
      (debug deny) ; log all denied operations to /var/log/system.log
      <%= rules.join("\n") %>
      (allow file-write*
          (literal "/dev/ptmx")
          (literal "/dev/dtracehelper")
          (literal "/dev/null")
          (literal "/dev/random")
          (literal "/dev/zero")
          (regex #"^/dev/fd/[0-9]+$")
          (regex #"^/dev/tty[a-z0-9]*$")
          )
      (deny file-write*) ; deny non-allowlist file write operations
      (deny file-write-setugid) ; deny non-allowlist file write SUID/SGID operations
      (deny file-write-mode) ; deny non-allowlist file write mode operations
      (allow process-exec
          (literal "/bin/ps")
          (with no-sandbox)
          ) ; allow certain processes running without sandbox
      (allow default) ; allow everything else
    ERB

    sig { returns(T::Array[String]) }
    attr_reader :rules

    sig { void }
    def initialize
      @rules = T.let([], T::Array[String])
    end

    sig { params(rule: SandboxRule).void }
    def add_rule(rule)
      s = +"("
      s << (rule.allow ? "allow" : "deny")
      s << " #{rule.operation}"
      s << " (#{rule.filter})" if rule.filter
      s << " (with #{rule.modifier})" if rule.modifier
      s << ")"
      @rules << s.freeze
    end

    sig { returns(String) }
    def dump
      ERB.new(SEATBELT_ERB).result(binding)
    end
  end
  private_constant :SandboxProfile
end

require "extend/os/sandbox"
