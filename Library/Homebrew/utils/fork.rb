# typed: strict
# frozen_string_literal: true

require "fcntl"
require "utils/socket"

module Utils
  sig { params(child_error: T::Hash[String, T.untyped]).returns(Exception) }
  def self.rewrite_child_error(child_error)
    inner_class = Object.const_get(child_error["json_class"])
    error = if child_error["cmd"] && inner_class == ErrorDuringExecution
      ErrorDuringExecution.new(child_error["cmd"],
                               status: child_error["status"],
                               output: child_error["output"])
    elsif child_error["cmd"] && inner_class == BuildError
      # We fill `BuildError#formula` and `BuildError#options` in later,
      # when we rescue this in `FormulaInstaller#build`.
      BuildError.new(nil, child_error["cmd"], child_error["args"], child_error["env"])
    elsif inner_class == Interrupt
      Interrupt.new
    else
      # Everything other error in the child just becomes a RuntimeError.
      RuntimeError.new <<~EOS
        An exception occurred within a child process:
          #{inner_class}: #{child_error["m"]}
      EOS
    end

    error.set_backtrace child_error["b"]

    error
  end

  sig { returns(IO) }
  def self.safe_fork_error_pipe
    # Non-WSL children still receive this over AF_UNIX; the WSL branch uses an inherited pipe FD.
    if !ENV.key?("HOMEBREW_ERROR_PIPE") && (error_pipe_fd = ENV.fetch("HOMEBREW_ERROR_PIPE_FD", nil))
      return IO.new(error_pipe_fd.to_i, "w")
    end

    UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io)
  end

  # When using this function, remember to call `exec` as soon as reasonably possible.
  # This function does not protect against the pitfalls of what you can do pre-exec in a fork.
  # See `man fork` for more information.
  sig {
    params(directory: T.nilable(String), yield_parent: T::Boolean,
           blk: T.proc.params(arg0: T.nilable(String)).void).void
  }
  def self.safe_fork(directory: nil, yield_parent: false, &blk)
    require "json/add/exception"

    block = proc do |tmpdir|
      if safe_fork_use_error_pipe_fd?
        safe_fork_with_error_pipe_fd(yield_parent:, &blk)
      else
        safe_fork_with_error_socket(tmpdir, yield_parent:, &blk)
      end
    end

    if directory
      block.call(directory)
    else
      Dir.mktmpdir("homebrew-fork", HOMEBREW_TEMP, &block)
    end
  end

  sig { returns(T::Boolean) }
  def self.safe_fork_use_error_pipe_fd?
    !!(defined?(OS::Linux) && T.unsafe(OS::Linux).wsl?)
  end
  private_class_method :safe_fork_use_error_pipe_fd?

  sig { params(yield_parent: T::Boolean, blk: T.proc.params(arg0: T.nilable(String)).void).void }
  def self.safe_fork_with_error_pipe_fd(yield_parent:, &blk)
    read, write = IO.pipe

    pid = fork do
      # bootsnap doesn't like these forked processes
      ENV["HOMEBREW_NO_BOOTSNAP"] = "1"
      read.close
      # WSL can reject AF_UNIX sockets, so child execs keep this FD open to report errors.
      flags = write.fcntl(Fcntl::F_GETFD, 0)
      write.fcntl(Fcntl::F_SETFD, flags & ~Fcntl::FD_CLOEXEC)
      error_pipe = write.fileno.to_s
      ENV["HOMEBREW_ERROR_PIPE_FD"] = error_pipe
      ENV.delete("HOMEBREW_ERROR_PIPE")

      Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid

      yield(error_pipe)
    # This could be any type of exception, so rescue them all.
    rescue Exception => e # rubocop:disable Lint/RescueException
      error_hash = JSON.parse e.to_json

      # Special case: We need to recreate ErrorDuringExecutions
      # for proper error messages and because other code expects
      # to rescue them further down.
      if e.is_a?(ErrorDuringExecution)
        error_hash["cmd"] = e.cmd
        error_hash["status"] = if e.status.is_a?(Process::Status)
          {
            exitstatus: e.exitstatus,
            termsig:    e.termsig,
          }
        else
          e.status
        end
        error_hash["output"] = e.output
      end

      write.puts error_hash.to_json
      write.close

      exit!
    else
      exit!(true)
    end

    write.close

    begin
      yield(nil) if yield_parent

      data = read.read
      read.close
      Process.waitpid(pid)
    rescue Interrupt
      read.close unless read.closed?
      Process.waitpid(pid)
    end

    # 130 is the exit status for a process interrupted via Ctrl-C.
    raise Interrupt if $CHILD_STATUS.exitstatus == 130
    raise Interrupt if $CHILD_STATUS.termsig == Signal.list["INT"]

    if data.present?
      error_hash = JSON.parse(data.lines.fetch(0))
      raise rewrite_child_error(error_hash)
    end

    raise ChildProcessError, $CHILD_STATUS unless $CHILD_STATUS.success?
  end
  private_class_method :safe_fork_with_error_pipe_fd

  sig { params(directory: String, yield_parent: T::Boolean, blk: T.proc.params(arg0: T.nilable(String)).void).void }
  def self.safe_fork_with_error_socket(directory, yield_parent:, &blk)
    UNIXServerExt.open("#{directory}/socket") do |server|
      read, write = IO.pipe

      pid = fork do
        # bootsnap doesn't like these forked processes
        ENV["HOMEBREW_NO_BOOTSNAP"] = "1"
        error_pipe = server.path
        ENV["HOMEBREW_ERROR_PIPE"] = error_pipe
        server.close
        read.close
        write.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

        Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid

        yield(error_pipe)
      # This could be any type of exception, so rescue them all.
      rescue Exception => e # rubocop:disable Lint/RescueException
        error_hash = JSON.parse e.to_json

        # Special case: We need to recreate ErrorDuringExecutions
        # for proper error messages and because other code expects
        # to rescue them further down.
        if e.is_a?(ErrorDuringExecution)
          error_hash["cmd"] = e.cmd
          error_hash["status"] = if e.status.is_a?(Process::Status)
            {
              exitstatus: e.exitstatus,
              termsig:    e.termsig,
            }
          else
            e.status
          end
          error_hash["output"] = e.output
        end

        write.puts error_hash.to_json
        write.close

        exit!
      else
        exit!(true)
      end

      begin
        yield(nil) if yield_parent

        begin
          socket = server.accept_nonblock
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
          retry unless Process.waitpid(pid, Process::WNOHANG)
        else
          socket.send_io(write)
          socket.close
        end
        write.close
        data = read.read
        read.close
        Process.waitpid(pid) unless socket.nil?
      rescue Interrupt
        Process.waitpid(pid)
      end

      # 130 is the exit status for a process interrupted via Ctrl-C.
      raise Interrupt if $CHILD_STATUS.exitstatus == 130
      raise Interrupt if $CHILD_STATUS.termsig == Signal.list["INT"]

      if data.present?
        error_hash = JSON.parse(data.lines.fetch(0))
        raise rewrite_child_error(error_hash)
      end

      raise ChildProcessError, $CHILD_STATUS unless $CHILD_STATUS.success?
    end
  end
  private_class_method :safe_fork_with_error_socket
end
