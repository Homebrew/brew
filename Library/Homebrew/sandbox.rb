# typed: true
# frozen_string_literal: true

require "erb"
require "io/console"
require "pty"
require "tempfile"

# Helper class for running a sub-process inside of a sandboxed environment.
#
# @api private
class Sandbox
  SANDBOX_EXEC = "/usr/bin/sandbox-exec"
  private_constant :SANDBOX_EXEC

  sig { returns(T::Boolean) }
  def self.available?
    false
  end

  sig { void }
  def initialize
    @profile = SandboxProfile.new
  end

  def record_log(file)
    @logfile = file
  end

  def add_rule(rule)
    @profile.add_rule(rule)
  end

  def allow_write(path, options = {})
    add_rule allow: true, operation: "file-write*", filter: path_filter(path, options[:type])
    add_rule allow: true, operation: "file-write-setugid", filter: path_filter(path, options[:type])
  end

  def deny_write(path, options = {})
    add_rule allow: false, operation: "file-write*", filter: path_filter(path, options[:type])
  end

  def allow_write_path(path)
    allow_write path, type: :subpath
  end

  def deny_write_path(path)
    deny_write path, type: :subpath
  end

  def allow_write_temp_and_cache
    allow_write_path "/private/tmp"
    allow_write_path "/private/var/tmp"
    allow_write "^/private/var/folders/[^/]+/[^/]+/[C,T]/", type: :regex
    allow_write_path HOMEBREW_TEMP
    allow_write_path HOMEBREW_CACHE
  end

  def allow_cvs
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.cvspass"
  end

  def allow_fossil
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil"
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/.fossil-journal"
  end

  def allow_write_cellar(formula)
    allow_write_path formula.rack
    allow_write_path formula.etc
    allow_write_path formula.var
  end

  # Xcode projects expect access to certain cache/archive dirs.
  def allow_write_xcode
    allow_write_path "#{Dir.home(ENV.fetch("USER"))}/Library/Developer"
  end

  def allow_write_log(formula)
    allow_write_path formula.logs
  end

  def deny_write_homebrew_repository
    deny_write HOMEBREW_BREW_FILE
    if HOMEBREW_PREFIX.to_s == HOMEBREW_REPOSITORY.to_s
      deny_write_path HOMEBREW_LIBRARY
      deny_write_path HOMEBREW_REPOSITORY/".git"
    else
      deny_write_path HOMEBREW_REPOSITORY
    end
  end

  def exec(*args)
    seatbelt = Tempfile.new(["homebrew", ".sb"], HOMEBREW_TEMP)
    seatbelt.write(@profile.dump)
    seatbelt.close
    @start = Time.now

    begin
      command = [SANDBOX_EXEC, "-f", seatbelt.path, *args]
      # Start sandbox in a pseudoterminal to prevent access of the parent terminal.
      PTY.spawn(*command) do |r, w, pid|
        # Set the PTY's window size to match the parent terminal.
        # Some formula tests are sensitive to the terminal size and fail if this is not set.
        winch = proc do |_sig|
          w.winsize = if $stdout.tty?
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
            IO.copy_stream($stdin, w)
          rescue Errno::EIO
            # stdin is unavailable - move on.
          end

          r.each_char { |c| print(c) }

          Process.wait(pid)
        ensure
          stdin_thread&.kill
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
      raise ErrorDuringExecution.new(command, status: $CHILD_STATUS) unless $CHILD_STATUS.success?
    rescue
      @failed = true
      raise
    ensure
      seatbelt.unlink
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

  private

  def expand_realpath(path)
    raise unless path.absolute?

    path.exist? ? path.realpath : expand_realpath(path.parent)/path.basename
  end

  def path_filter(path, type)
    case type
    when :regex        then "regex #\"#{path}\""
    when :subpath      then "subpath \"#{expand_realpath(Pathname.new(path))}\""
    when :literal, nil then "literal \"#{expand_realpath(Pathname.new(path))}\""
    end
  end

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
      (allow process-exec
          (literal "/bin/ps")
          (with no-sandbox)
          ) ; allow certain processes running without sandbox
      (allow default) ; allow everything else
    ERB

    attr_reader :rules

    sig { void }
    def initialize
      @rules = []
    end

    def add_rule(rule)
      s = +"("
      s << (rule[:allow] ? "allow" : "deny")
      s << " #{rule[:operation]}"
      s << " (#{rule[:filter]})" if rule[:filter]
      s << " (with #{rule[:modifier]})" if rule[:modifier]
      s << ")"
      @rules << s.freeze
    end

    def dump
      ERB.new(SEATBELT_ERB).result(binding)
    end
  end
  private_constant :SandboxProfile
end

require "extend/os/sandbox"
