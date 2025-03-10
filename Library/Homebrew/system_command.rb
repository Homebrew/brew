# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "plist"
require "shellwords"
require "uri"

require "context"
require "extend/io"
require "utils/timer"

# Class for running sub-processes and capturing their output and exit status.
#
# @api internal
class SystemCommand
  # Helper functions for calling {SystemCommand.run}.
  #
  # @api internal
  module Mixin
    # Run a fallible system command.
    #
    # @api internal
    def system_command(executable, **options)
      SystemCommand.run(executable, **options)
    end

    # Run an infallible system command.
    #
    # @api internal
    def system_command!(command, **options)
      SystemCommand.run!(command, **options)
    end
  end

  include Context

  def self.run(executable, **options)
    new(executable, **options).run!
  end

  def self.run!(command, **options)
    run(command, **options, must_succeed: true)
  end

  sig { returns(SystemCommand::Result) }
  def run!
    $stderr.puts redact_secrets(command.shelljoin.gsub('\=', "="), @secrets) if verbose? || debug?

    @output = []

    each_output_line do |type, line|
      case type
      when :stdout
        case @print_stdout
        when true
          $stdout << redact_secrets(line, @secrets)
        when :debug
          $stderr << redact_secrets(line, @secrets) if debug?
        end
        @output << [:stdout, line]
      when :stderr
        case @print_stderr
        when true
          $stderr << redact_secrets(line, @secrets)
        when :debug
          $stderr << redact_secrets(line, @secrets) if debug?
        end
        @output << [:stderr, line]
      end
    end

    result = Result.new(command, @output, @status, secrets: @secrets)
    result.assert_success! if must_succeed?
    result
  end

  sig {
    params(
      executable:   T.any(String, Pathname),
      args:         T::Array[T.any(String, Integer, Float, URI::Generic)],
      sudo:         T::Boolean,
      sudo_as_root: T::Boolean,
      env:          T::Hash[String, String],
      input:        T.any(String, T::Array[String]),
      must_succeed: T::Boolean,
      print_stdout: T.any(T::Boolean, Symbol),
      print_stderr: T.any(T::Boolean, Symbol),
      debug:        T.nilable(T::Boolean),
      verbose:      T.nilable(T::Boolean),
      secrets:      T.any(String, T::Array[String]),
      chdir:        T.any(String, Pathname),
      reset_uid:    T::Boolean,
      timeout:      T.nilable(T.any(Integer, Float)),
    ).void
  }
  def initialize(
    executable,
    args: [],
    sudo: false,
    sudo_as_root: false,
    env: {},
    input: [],
    must_succeed: false,
    print_stdout: false,
    print_stderr: true,
    debug: nil,
    verbose: false,
    secrets: [],
    chdir: T.unsafe(nil),
    reset_uid: false,
    timeout: nil
  )
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
    @input = Array(input)
    @must_succeed = must_succeed
    @print_stdout = print_stdout
    @print_stderr = print_stderr
    @debug = debug
    @verbose = verbose
    @secrets = (Array(secrets) + ENV.sensitive_environment.values).uniq
    @chdir = chdir
    @reset_uid = reset_uid
    @timeout = timeout
  end

  sig { returns(T::Array[String]) }
  def command
    [*command_prefix, executable.to_s, *expanded_args]
  end

  private

  attr_reader :executable, :args, :input, :chdir, :env

  sig { returns(T::Boolean) }
  def must_succeed? = @must_succeed

  sig { returns(T::Boolean) }
  def reset_uid? = @reset_uid

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
    askpass_flags = ENV.key?("SUDO_ASKPASS") ? ["-A"] : []
    user_flags = []
    if Homebrew::EnvConfig.sudo_through_sudo_user?
      raise ArgumentError, "HOMEBREW_SUDO_THROUGH_SUDO_USER set but SUDO_USER unset!" if homebrew_sudo_user.blank?

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
    @expanded_args ||= args.map do |arg|
      if arg.respond_to?(:to_path)
        File.absolute_path(arg)
      elsif arg.is_a?(Integer) || arg.is_a?(Float) || arg.is_a?(URI::Generic)
        arg.to_s
      else
        arg.to_str
      end
    end
  end

  class ProcessTerminatedInterrupt < StandardError; end
  private_constant :ProcessTerminatedInterrupt

  sig { params(block: T.proc.params(type: Symbol, line: String).void).void }
  def each_output_line(&block)
    executable, *args = command
    options = {
      # Create a new process group so that we can send `SIGINT` from
      # parent to child rather than the child receiving `SIGINT` directly.
      pgroup: sudo? ? nil : true,
    }
    options[:chdir] = chdir if chdir

    raw_stdin, raw_stdout, raw_stderr, raw_wait_thr = exec3(env, executable, *args, **options)

    write_input_to(raw_stdin)
    raw_stdin.close_write

    thread_context = Context.current
    thread_ready_queue = Queue.new
    thread_done_queue = Queue.new
    line_thread = Thread.new do
      # Ensure the new thread inherits the current context.
      Context.current = thread_context

      Thread.handle_interrupt(ProcessTerminatedInterrupt => :never) do
        thread_ready_queue << true
        each_line_from [raw_stdout, raw_stderr], &block
      end
      thread_done_queue.pop
    rescue ProcessTerminatedInterrupt
      nil
    end

    end_time = Time.now + @timeout if @timeout
    raise Timeout::Error if raw_wait_thr.join(Utils::Timer.remaining(end_time)).nil?

    @status = raw_wait_thr.value
  rescue Interrupt
    Process.kill("INT", raw_wait_thr.pid) if raw_wait_thr && !sudo?
    raise Interrupt
  ensure
    if line_thread
      thread_ready_queue.pop
      line_thread.raise ProcessTerminatedInterrupt.new
      thread_done_queue << true
      line_thread.join
    end
    raw_stdin&.close
    raw_stdout&.close
    raw_stderr&.close
  end

  sig {
    params(
      env:        T::Hash[String, String],
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

    pid = fork do
      Process::UID.change_privilege(Process.euid) if reset_uid? && Process.euid != Process.uid

      exec(
        env.merge({ "COLUMNS" => Tty.width.to_s }),
        [executable, executable],
        *args,
        **options,
      )
    rescue SystemCallError => e
      $stderr.puts(e.message)
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
    input.each { raw_stdin.write(_1) }
  end

  sig { params(sources: T::Array[IO], _block: T.proc.params(type: Symbol, line: String).void).void }
  def each_line_from(sources, &_block)
    sources = {
      sources[0] => :stdout,
      sources[1] => :stderr,
    }

    pending_interrupt = T.let(false, T::Boolean)

    until pending_interrupt || sources.empty?
      readable_sources = T.let([], T::Array[IO])
      begin
        Thread.handle_interrupt(ProcessTerminatedInterrupt => :on_blocking) do
          readable_sources = T.must(IO.select(sources.keys)).fetch(0)
        end
      rescue ProcessTerminatedInterrupt
        readable_sources = sources.keys
        pending_interrupt = true
      end

      readable_sources.each do |source|
        loop do
          line = source.readline_nonblock || ""
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

    attr_accessor :command, :status, :exit_status

    sig {
      params(
        command: T::Array[String],
        output:  T::Array[[Symbol, String]],
        status:  Process::Status,
        secrets: T::Array[String],
      ).void
    }
    def initialize(command, output, status, secrets:)
      @command       = command
      @output        = output
      @status        = status
      @exit_status   = status.exitstatus
      @secrets       = secrets
    end

    sig { void }
    def assert_success!
      return if @status.success?

      raise ErrorDuringExecution.new(command, status: @status, output: @output, secrets: @secrets)
    end

    sig { returns(String) }
    def stdout
      @stdout ||= @output.select { |type,| type == :stdout }
                         .map { |_, line| line }
                         .join
    end

    sig { returns(String) }
    def stderr
      @stderr ||= @output.select { |type,| type == :stderr }
                         .map { |_, line| line }
                         .join
    end

    sig { returns(String) }
    def merged_output
      @merged_output ||= @output.map { |_, line| line }
                                .join
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

    sig { returns(T.nilable(T.any(Array, Hash))) }
    def plist
      @plist ||= begin
        output = stdout

        output = output.sub(/\A(.*?)(\s*<\?\s*xml)/m) do
          warn_plist_garbage(T.must(Regexp.last_match(1)))
          Regexp.last_match(2)
        end

        output = output.sub(%r{(<\s*/\s*plist\s*>\s*)(.*?)\Z}m) do
          warn_plist_garbage(T.must(Regexp.last_match(2)))
          Regexp.last_match(1)
        end

        Plist.parse_xml(output, marshal: false)
      end
    end

    sig { params(garbage: String).void }
    def warn_plist_garbage(garbage)
      return unless verbose?
      return unless garbage.match?(/\S/)

      opoo "Received non-XML output from #{Formatter.identifier(command.first)}:"
      $stderr.puts garbage.strip
    end
    private :warn_plist_garbage
  end
end
