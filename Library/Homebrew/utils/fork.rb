# typed: strict
# frozen_string_literal: true

require "fcntl"
require "utils/socket"

module Utils
  sig { returns(IO) }
  def self.forked_child_error_pipe
    UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE"), &:recv_io).tap do |error_pipe|
      error_pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    end
  end

  sig { params(error: Exception).returns(T::Hash[String, T.untyped]) }
  def self.child_error_hash(error)
    require "json/add/exception"

    error_hash = T.cast(JSON.parse(error.to_json), T::Hash[String, T.untyped])
    case error
    when BuildError
      error_hash["cmd"] = error.cmd
      error_hash["args"] = error.args
      error_hash["env"] = error.env
    when ErrorDuringExecution
      error_hash["cmd"] = error.cmd
      error_hash["status"] = if error.status.is_a?(Process::Status)
        {
          exitstatus: error.exitstatus,
          termsig:    error.termsig,
        }
      else
        error.status
      end
      error_hash["output"] = error.output
    end
    error_hash
  end

  sig { params(error_pipe: T.nilable(IO), error: Exception).void }
  def self.report_forked_child_error(error_pipe, error)
    error_pipe&.puts child_error_hash(error).to_json
    error_pipe&.close
  end

  sig { params(child_error: T::Hash[String, T.untyped]).returns(Exception) }
  def self.rewrite_child_error(child_error)
    # The error class name comes from the forked child's serialised JSON.
    # rubocop:disable Sorbet/ConstantsFromStrings
    inner_class = Object.const_get(child_error["json_class"])
    # rubocop:enable Sorbet/ConstantsFromStrings
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

  # When using this function, remember to call `exec` as soon as reasonably possible.
  # This function does not protect against the pitfalls of what you can do pre-exec in a fork.
  # See `man fork` for more information.
  sig {
    params(directory: T.nilable(String), yield_parent: T::Boolean,
           _blk: T.proc.params(arg0: T.nilable(String)).void).void
  }
  def self.safe_fork(directory: nil, yield_parent: false, &_blk)
    block = proc do |tmpdir|
      UNIXServerExt.open("#{tmpdir}/socket") do |server|
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
          report_forked_child_error(write, e)

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

    if directory
      block.call(directory)
    else
      Dir.mktmpdir("homebrew-fork", HOMEBREW_TEMP, &block)
    end
  end
end
