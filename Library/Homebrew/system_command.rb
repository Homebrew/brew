# typed: strict
# frozen_string_literal: true

require "English"
require "shellwords"
require "stringio"

require "context"
require "readline_nonblock"
require "utils/timer"
require "utils/output"

# Class for running sub-processes and capturing their output and exit status.
#
# @api internal
class SystemCommand
  # Helper functions for calling {SystemCommand.run}.
  #
  # @api internal
  module Mixin
    sig { overridable.returns(T.nilable(Sandbox)) }
    def command_sandbox = nil

    # Run a fallible system command.
    #
    # @api internal
    sig {
      params(
        executable:   T.any(String, Pathname),
        args:         T::Array[T.any(String, Integer, Float, Pathname)],
        sudo:         T.nilable(T::Boolean),
        sudo_as_root: T::Boolean,
        env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
        input:        T.any(String, T::Array[String]),
        must_succeed: T::Boolean,
        print_stdout: T.any(T::Boolean, Symbol),
        print_stderr: T.any(T::Boolean, Symbol),
        debug:        T.nilable(T::Boolean),
        verbose:      T.nilable(T::Boolean),
        secrets:      T.any(String, T::Array[String]),
        chdir:        T.nilable(T.any(String, Pathname)),
        timeout:      T.nilable(T.any(Integer, Float)),
      ).returns(SystemCommand::Result)
    }
    def system_command(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [],
                       must_succeed: false, print_stdout: false, print_stderr: true, debug: nil, verbose: nil,
                       secrets: [], chdir: nil, timeout: nil)
      if (sandbox = command_sandbox)
        Kernel.raise ArgumentError, "Sandboxed commands cannot use sudo" if sudo || sudo_as_root

        return sandbox.capture(executable, args:, env:, input:, must_succeed:, print_stdout:, print_stderr:,
                               debug:, verbose:, secrets:, chdir:, timeout:)
      end

      SystemCommand.run(executable, args:, sudo:, sudo_as_root:, env:, input:, must_succeed:, print_stdout:,
                        print_stderr:, debug:, verbose:, secrets:, chdir:, timeout:)
    end

    # Run an infallible system command.
    #
    # @api internal
    sig {
      params(
        executable:   T.any(String, Pathname),
        args:         T::Array[T.any(String, Integer, Float, Pathname)],
        sudo:         T.nilable(T::Boolean),
        sudo_as_root: T::Boolean,
        env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
        input:        T.any(String, T::Array[String]),
        print_stdout: T.any(T::Boolean, Symbol),
        print_stderr: T.any(T::Boolean, Symbol),
        debug:        T.nilable(T::Boolean),
        verbose:      T.nilable(T::Boolean),
        secrets:      T.any(String, T::Array[String]),
        chdir:        T.nilable(T.any(String, Pathname)),
        timeout:      T.nilable(T.any(Integer, Float)),
      ).returns(SystemCommand::Result)
    }
    def system_command!(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [],
                        print_stdout: false, print_stderr: true, debug: nil, verbose: nil, secrets: [],
                        chdir: nil, timeout: nil)
      system_command(executable, args:, sudo:, sudo_as_root:, env:, input:, must_succeed: true, print_stdout:,
                     print_stderr:, debug:, verbose:, secrets:, chdir:, timeout:)
    end
  end

  # Positional command helpers used by the Formula DSL.
  module Helpers
    sig { params(executable: T.any(String, Pathname), args: T.any(String, Pathname)).void }
    def safe_system(executable, *args)
      SystemCommand.safe_system(executable, *args)
    end

    sig { params(executable: T.any(String, Pathname), args: T.any(String, Pathname)).returns(T::Boolean) }
    def quiet_system(executable, *args)
      SystemCommand.quiet_system(executable, *args)
    end
  end

  include Context

  sig { params(sandbox: T.nilable(Sandbox)).void }
  attr_writer :sandbox

  sig { params(sandbox_inheritance: IO).returns(IO) }
  attr_writer :sandbox_inheritance

  sig {
    params(
      executable:   T.any(String, Pathname),
      args:         T::Array[T.any(String, Integer, Float, Pathname)],
      sudo:         T.nilable(T::Boolean),
      sudo_as_root: T::Boolean,
      env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      input:        T.any(String, T::Array[String]),
      must_succeed: T::Boolean,
      print_stdout: T.any(T::Boolean, Symbol),
      print_stderr: T.any(T::Boolean, Symbol),
      debug:        T.nilable(T::Boolean),
      verbose:      T.nilable(T::Boolean),
      secrets:      T.any(String, T::Array[String]),
      chdir:        T.nilable(T.any(String, Pathname)),
      timeout:      T.nilable(T.any(Integer, Float)),
    ).returns(SystemCommand::Result)
  }
  def self.run(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [], must_succeed: false,
               print_stdout: false, print_stderr: true, debug: nil, verbose: nil, secrets: [], chdir: nil,
               timeout: nil)
    # Only use sudo: nil for operations that can safely be retried.
    if sudo.nil?
      result = new(executable, args:, sudo: false, sudo_as_root: false, env:, input:, must_succeed: false,
                   print_stdout:, print_stderr: Homebrew::EnvConfig.no_sudo? ? print_stderr : false,
                   debug:, verbose:, secrets:, chdir:, timeout:).run!
      if result.success? || !sudo_available?
        result.assert_success! if must_succeed
        return result
      end
      sudo = true
    end

    new(executable, args:, sudo:, sudo_as_root:, env:, input:, must_succeed:, print_stdout:, print_stderr:, debug:,
        verbose:, secrets:, chdir:, timeout:).run!
  end

  # Check access once, when a command first needs sudo.
  sig { returns(T::Boolean) }
  def self.sudo_available?
    return false if Homebrew::EnvConfig.no_sudo?
    return true if ENV["HOMEBREW_SUDO_CHECKED"] == "1"

    ENV["HOMEBREW_NO_SUDO"] = "1" unless run("/bin/bash", args:         [HOMEBREW_LIBRARY_PATH/"utils/sudo.sh"],
                                                          print_stderr: false).success?
    ENV["HOMEBREW_SUDO_CHECKED"] = "1"
    !Homebrew::EnvConfig.no_sudo?
  end

  sig {
    params(
      executable:   T.any(String, Pathname),
      args:         T::Array[T.any(String, Integer, Float, Pathname)],
      sudo:         T.nilable(T::Boolean),
      sudo_as_root: T::Boolean,
      env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      input:        T.any(String, T::Array[String]),
      must_succeed: T::Boolean,
      print_stdout: T.any(T::Boolean, Symbol),
      print_stderr: T.any(T::Boolean, Symbol),
      debug:        T.nilable(T::Boolean),
      verbose:      T.nilable(T::Boolean),
      secrets:      T.any(String, T::Array[String]),
      chdir:        T.nilable(T.any(String, Pathname)),
      timeout:      T.nilable(T.any(Integer, Float)),
    ).returns(SystemCommand::Result)
  }
  def self.run!(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [], must_succeed: true,
                print_stdout: false, print_stderr: true, debug: nil, verbose: nil, secrets: [], chdir: nil,
                timeout: nil)
    run(executable, args:, sudo:, sudo_as_root:, env:, input:, must_succeed:, print_stdout:, print_stderr:,
        debug:, verbose:, secrets:, chdir:, timeout:)
  end

  # Run a command attached to the caller's standard streams and terminal,
  # raising if it fails. Unlike {SystemCommand.run!} nothing is captured, so
  # interactive programs such as editors and pagers work.
  sig {
    params(
      executable: T.nilable(T.any(String, Pathname)),
      args:       T.nilable(T.any(String, Pathname)),
      env:        T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      out:        T.nilable(Symbol),
    ).void
  }
  def self.safe_system(executable, *args, env: {}, out: nil)
    raise ArgumentError, "Missing executable" if executable.nil?
    raise ArgumentError, "Invalid nil command argument" if args.any?(&:nil?)

    args = args.compact
    if Context.current.verbose?
      command = "#{executable} #{args * " "}".gsub(RUBY_PATH.to_s, "ruby")
                                             .gsub($LOAD_PATH.join(File::PATH_SEPARATOR), "$LOAD_PATH")
      ((out == :err) ? $stderr : $stdout).puts Formatter.redact_secrets(command, secrets)
    end
    return if attached_success?(executable, args, env:, out:)

    raise ErrorDuringExecution.new([executable, *args], status: $CHILD_STATUS, secrets:)
  end

  # Run a command attached to the caller's standard input with its output
  # discarded, returning whether it succeeded.
  # Preserve the existing Formula DSL method name.
  # rubocop:disable Naming/PredicateMethod
  sig {
    params(
      executable: T.nilable(T.any(String, Pathname)),
      args:       T.nilable(T.any(String, Pathname)),
      env:        T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
    ).returns(T::Boolean)
  }
  def self.quiet_system(executable, *args, env: {})
    return false if executable.nil? || args.any?(&:nil?)

    # Redirect output streams to `/dev/null` instead of closing as some programs
    # will fail to execute if they can't write to an open stream.
    attached_success?(executable, args.compact, env:, out: File::NULL, err: File::NULL)
  end
  # rubocop:enable Naming/PredicateMethod

  sig { returns(T::Array[String]) }
  private_class_method def self.secrets
    require "extend/ENV"
    ENV.sensitive_environment.values
  end

  sig {
    params(
      executable: T.any(String, Pathname),
      args:       T::Array[T.any(String, Pathname)],
      env:        T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      out:        T.nilable(T.any(String, Symbol)),
      err:        T.nilable(String),
    ).returns(T::Boolean)
  }
  private_class_method def self.attached_success?(executable, args, env:, out: nil, err: nil)
    # Like `system(3)`, keep the terminal's interrupt from raising in the parent
    # so a command that handles it, such as an editor, keeps running. Trapping
    # with a block rather than `IGNORE` leaves the child its default handler.
    old_sigint_handler = Signal.trap(:INT) { nil }
    old_sigquit_handler = Signal.trap(:QUIT) { nil }
    begin
      Kernel.system(env.transform_values { |value| value&.to_s }, executable.to_s, *args.map(&:to_s),
                    **{ out:, err: }.compact)
    ensure
      Signal.trap(:INT, old_sigint_handler)
      Signal.trap(:QUIT, old_sigquit_handler)
    end
    raise Interrupt if $CHILD_STATUS.termsig == Signal.list.fetch("INT") || $CHILD_STATUS.exitstatus == 130

    $CHILD_STATUS.success? || false
  end

  sig { returns(SystemCommand::Result) }
  def run!
    $stderr.puts Formatter.redact_secrets(command.shelljoin.gsub('\=', "="), @secrets) if verbose? && debug?

    output = T.let([], T::Array[[Symbol, String]])

    status = each_output_line do |type, line|
      case type
      when :stdout
        case @print_stdout
        when true
          $stdout << Formatter.redact_secrets(line, @secrets)
        when :debug
          $stderr << Formatter.redact_secrets(line, @secrets) if debug?
        end
        output << [:stdout, line]
      when :stderr
        case @print_stderr
        when true
          $stderr << Formatter.redact_secrets(line, @secrets)
        when :debug
          $stderr << Formatter.redact_secrets(line, @secrets) if debug?
        end
        output << [:stderr, line]
      end
    end

    result = Result.new(command, output, status, secrets: @secrets)
    result.assert_success! if must_succeed?
    result
  end

  sig {
    params(
      executable:   T.any(String, Pathname),
      args:         T::Array[T.any(String, Integer, Float, Pathname)],
      sudo:         T::Boolean,
      sudo_as_root: T::Boolean,
      env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      input:        T.any(String, T::Array[String]),
      must_succeed: T::Boolean,
      print_stdout: T.any(T::Boolean, Symbol),
      print_stderr: T.any(T::Boolean, Symbol),
      debug:        T.nilable(T::Boolean),
      verbose:      T.nilable(T::Boolean),
      secrets:      T.any(String, T::Array[String]),
      chdir:        T.nilable(T.any(String, Pathname)),
      timeout:      T.nilable(T.any(Integer, Float)),
    ).void
  }
  def initialize(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [], must_succeed: false,
                 print_stdout: false, print_stderr: true, debug: nil, verbose: nil, secrets: [], chdir: nil,
                 timeout: nil)
    require "extend/ENV"
    @executable = executable
    @args = args

    raise ArgumentError, "`sudo_as_root` cannot be set if sudo is false" if !sudo && sudo_as_root

    if print_stdout.is_a?(Symbol) && print_stdout != :debug
      raise ArgumentError, "`print_stdout` is not a valid symbol"
    end
    if print_stderr.is_a?(Symbol) && print_stderr != :debug
      raise ArgumentError, "`print_stderr` is not a valid symbol"
    end

    @sudo = sudo
    @sudo_as_root = sudo_as_root
    env.each_key do |name|
      next if /^[\w&&\D]\w*$/.match?(name)

      raise ArgumentError, "Invalid variable name: #{name}"
    end
    @env = env
    @input = T.let(Array(input), T::Array[String])
    @must_succeed = must_succeed
    @print_stdout = print_stdout
    @print_stderr = print_stderr
    @debug = debug
    @verbose = verbose
    @secrets = T.let((Array(secrets) + ENV.sensitive_environment.values).uniq, T::Array[String])
    @chdir = chdir
    @timeout = timeout
    @sandbox = T.let(nil, T.nilable(Sandbox))
    @sandbox_inheritance = T.let(nil, T.nilable(IO))
  end

  sig { returns(T::Array[String]) }
  def command
    [*command_prefix, executable.to_s, *expanded_args]
  end

  private

  sig { returns(T.any(Pathname, String)) }
  attr_reader :executable

  sig { returns(T::Array[T.any(String, Integer, Float, Pathname)]) }
  attr_reader :args

  sig { returns(T::Array[String]) }
  attr_reader :input

  sig { returns(T.nilable(T.any(String, Pathname))) }
  attr_reader :chdir

  sig { returns(T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))]) }
  attr_reader :env

  sig { returns(T::Boolean) }
  def must_succeed? = @must_succeed

  sig { returns(T::Boolean) }
  def sudo? = @sudo

  sig { returns(T::Boolean) }
  def sudo_as_root? = @sudo_as_root

  sig { returns(T::Boolean) }
  def debug?
    return super if @debug.nil?

    @debug
  end

  sig { returns(T::Boolean) }
  def verbose?
    return super if @verbose.nil?

    @verbose
  end

  sig { returns(T::Array[String]) }
  def env_args
    set_variables = env.compact.map do |name, value|
      sanitized_name = Shellwords.escape(name)
      sanitized_value = Shellwords.escape(value)
      "#{sanitized_name}=#{sanitized_value}"
    end

    return [] if set_variables.empty?

    set_variables
  end

  sig { returns(T.nilable(String)) }
  def homebrew_sudo_user
    ENV.fetch("HOMEBREW_SUDO_USER", nil)
  end

  sig { returns(T::Array[String]) }
  def sudo_prefix
    unless self.class.sudo_available?
      raise ErrorDuringExecution.new([executable.to_s, *expanded_args], status: 1, secrets: @secrets,
                                     output: [[:stderr, "sudo is disabled by HOMEBREW_NO_SUDO.\n"]])
    end

    askpass_flags = ENV.key?("SUDO_ASKPASS") ? ["-A"] : []
    user_flags = []
    if Homebrew::EnvConfig.sudo_through_sudo_user?
      if homebrew_sudo_user.blank?
        raise ArgumentError, "`$HOMEBREW_SUDO_THROUGH_SUDO_USER` set but `$SUDO_USER` unset!"
      end

      user_flags += ["--prompt", "Password for %p:", "-u", homebrew_sudo_user,
                     *askpass_flags,
                     "-E", *env_args,
                     "--", "/usr/bin/sudo"]
    end
    user_flags += ["-u", "root"] if sudo_as_root?
    ["/usr/bin/sudo", *user_flags, *askpass_flags, "-E", *env_args, "--"]
  end

  sig { returns(T::Array[String]) }
  def env_prefix
    ["/usr/bin/env", *env_args]
  end

  sig { returns(T::Array[String]) }
  def command_prefix
    sudo? ? sudo_prefix : env_prefix
  end

  sig { returns(T::Array[String]) }
  def expanded_args
    @expanded_args ||= T.let(args.map do |arg|
      if arg.is_a?(Pathname)
        File.absolute_path(arg)
      else
        arg.to_s
      end
    end, T.nilable(T::Array[String]))
  end

  class ProcessTerminatedInterrupt < StandardError; end
  private_constant :ProcessTerminatedInterrupt

  sig { params(block: T.proc.params(type: Symbol, line: String).void).returns(Process::Status) }
  def each_output_line(&block)
    executable, *args = command
    options = {
      # Create a new process group so that we can send `SIGINT` from
      # parent to child rather than the child receiving `SIGINT` directly.
      pgroup: sudo? ? nil : true,
    }
    options[:chdir] = chdir if chdir

    raw_stdin, raw_stdout, raw_stderr, raw_wait_thr = exec3(env, executable, *args, **options)

    thread_context = Context.current
    thread_ready_queue = Queue.new
    thread_done_queue = Queue.new
    line_thread = Thread.new do
      # Ensure the new thread inherits the current context.
      Thread.current[:context] = thread_context

      Thread.handle_interrupt(ProcessTerminatedInterrupt => :never) do
        thread_ready_queue << true
        each_line_from [raw_stdout, raw_stderr], &block
      end
      thread_done_queue.pop
    rescue ProcessTerminatedInterrupt
      nil
    end

    write_input_to(raw_stdin)
    raw_stdin.close_write

    end_time = Time.now + @timeout if @timeout
    if raw_wait_thr.join(Utils::Timer.remaining(end_time)).nil?
      # Signal the whole process group so a timed-out command and its descendants
      # cannot outlive brew. `sudo` children share our group, so signal them directly.
      target = sudo? ? raw_wait_thr.pid : -raw_wait_thr.pid
      begin
        Process.kill("TERM", target)
        # `kill(0)` raises `ESRCH` once every process in the group has exited
        # (`EPERM` on macOS while only unreaped zombies remain).
        50.times do
          Process.kill(0, target)
          sleep 0.1
        end
        Process.kill("KILL", target)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
      raise Timeout::Error
    end

    raw_wait_thr.value
  rescue Interrupt
    if raw_wait_thr && !sudo?
      # The forked child may not have created its process group before sandbox setup.
      [-raw_wait_thr.pid, raw_wait_thr.pid].each do |target|
        Process.kill("INT", target)
        break
      rescue Errno::ESRCH
        next
      end
    end
    raise Interrupt
  ensure
    raw_stdin&.close
    if line_thread
      thread_ready_queue.pop
      line_thread.raise ProcessTerminatedInterrupt.new
      thread_done_queue << true
      line_thread.join
    end
    raw_stdout&.close
    raw_stderr&.close
  end

  sig {
    params(
      env:        T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
      executable: String,
      args:       String,
      options:    T.untyped,
    ).returns([IO, IO, IO, Thread])
  }
  def exec3(env, executable, *args, **options)
    in_r, in_w = IO.pipe
    options[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    options[:out] = out_w

    err_r, err_w = IO.pipe
    options[:err] = err_w

    exec_env = env.merge({ "COLUMNS" => Tty.width.to_s })
    if (inheritance = @sandbox_inheritance)
      options = options.merge(Sandbox::INHERITANCE_FD => inheritance)
    end

    # `Process.spawn` avoids running `malloc` in a `fork`ed child, which is not
    # fork-safe on macOS and can abort it. `fork` is kept as a fallback.
    pid = begin
      Process.spawn(exec_env, [executable, executable], *args, **options) unless @sandbox
    rescue SystemCallError
      nil
    end

    pid ||= fork do
      $stderr = err_w if @sandbox
      @sandbox&.apply!
      exec(exec_env, [executable, executable], *args, **options)
    # Never unwind into the parent's Ruby control flow after fork.
    rescue Exception => e # rubocop:disable Lint/RescueException
      err_w.puts(e.message)
      exit!(127)
    end
    wait_thr = Process.detach(pid)

    [in_w, out_r, err_r, wait_thr]
  rescue
    in_w&.close
    out_r&.close
    err_r&.close
    raise
  ensure
    in_r&.close
    out_w&.close
    err_w&.close
  end

  sig { params(raw_stdin: IO).void }
  def write_input_to(raw_stdin)
    input.each { raw_stdin.write(it) }
  end

  sig { params(sources: T::Array[IO], _block: T.proc.params(type: Symbol, line: String).void).void }
  def each_line_from(sources, &_block)
    sources = {
      sources[0] => :stdout,
      sources[1] => :stderr,
    }
    readers = T.let({}, T::Hash[IO, ReadlineNonblock])

    pending_interrupt = T.let(false, T::Boolean)

    until pending_interrupt || sources.empty?
      readable_sources = T.let([], T::Array[IO])
      begin
        Thread.handle_interrupt(ProcessTerminatedInterrupt => :on_blocking) do
          selected = IO.select(sources.keys)
          raise IOError, "No readable output streams for #{command.first}" if selected.nil?

          readable_sources = selected.fetch(0)
        end
      rescue ProcessTerminatedInterrupt
        readable_sources = sources.keys
        pending_interrupt = true
      end

      readable_sources.each do |source|
        reader = readers[source] ||= ReadlineNonblock.new(source)
        loop do
          line = reader.read
          yield(sources.fetch(source), line)
        end
      rescue EOFError
        source.close_read
        sources.delete(source)
      rescue IO::WaitReadable
        # We've got all the data that was ready, but the other end of the stream isn't finished yet
      end
    end

    sources.each_key(&:close_read)
  end

  # Result containing the output and exit status of a finished sub-process.
  class Result
    include Context
    include Utils::Output::Mixin

    sig { returns(T::Array[String]) }
    attr_accessor :command

    sig { returns(Process::Status) }
    attr_accessor :status

    sig { returns(T.nilable(Integer)) }
    attr_accessor :exit_status

    sig {
      params(
        command: T::Array[String],
        output:  T::Array[[T.any(String, Symbol), String]],
        status:  Process::Status,
        secrets: T::Array[String],
      ).void
    }
    def initialize(command, output, status, secrets:)
      @command       = command
      @output        = output
      @status        = status
      @exit_status   = T.let(status.exitstatus, T.nilable(Integer))
      @secrets       = secrets
    end

    sig { void }
    def assert_success!
      return if @status.success?

      raise ErrorDuringExecution.new(command, status: @status, output: @output, secrets: @secrets)
    end

    sig { returns(String) }
    def stdout
      @stdout ||= T.let(@output.select { |type,| type == :stdout }
                               .map { |_, line| line }
                               .join, T.nilable(String))
    end

    sig { returns(String) }
    def stderr
      @stderr ||= T.let(@output.select { |type,| type == :stderr }
                               .map { |_, line| line }
                               .join, T.nilable(String))
    end

    sig { returns(String) }
    def merged_output
      @merged_output ||= T.let(@output.map { |_, line| line }.join, T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def success?
      return false if @exit_status.nil?

      @exit_status.zero?
    end

    sig { returns([String, String, Process::Status]) }
    def to_ary
      [stdout, stderr, status]
    end
    alias to_a to_ary

    sig { returns(T.untyped) }
    def plist
      require "plist"
      @plist ||= T.let(begin
        output = stdout

        output = output.sub(/\A(.*?)(\s*<\?\s*xml)/m) do
          warn_plist_garbage(Regexp.last_match(1))
          Regexp.last_match(2)
        end

        output = output.sub(%r{(<\s*/\s*plist\s*>\s*)(.*?)\Z}m) do
          warn_plist_garbage(Regexp.last_match(2))
          Regexp.last_match(1)
        end

        Plist.parse_xml(output, marshal: false)
      end, T.untyped)
    end

    sig { params(garbage: T.nilable(String)).void }
    def warn_plist_garbage(garbage)
      return unless verbose?
      return unless garbage&.match?(/\S/)

      opoo "Received non-XML output from #{Formatter.identifier(command.first)}:"
      $stderr.puts garbage.strip
    end
    private :warn_plist_garbage
  end
end
