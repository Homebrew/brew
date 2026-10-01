# typed: strict
# frozen_string_literal: true

require "fcntl"
require "utils/socket"

module Utils
  # Bidirectional channel handed to a forked child whose parent passed
  # `child_message_handler` to `safe_fork`: request lines are written to the
  # error pipe and each response is read back from a second pipe.
  class ForkedChildChannel
    sig { params(error_pipe: IO, response_pipe: IO).void }
    def initialize(error_pipe, response_pipe)
      @error_pipe = error_pipe
      @response_pipe = response_pipe
    end

    sig { params(message: String).void }
    def puts(message)
      @error_pipe.puts message
    end

    sig { void }
    def flush
      @error_pipe.flush
    end

    sig { returns(T.nilable(String)) }
    def gets
      @response_pipe.gets
    end

    sig { void }
    def close
      @error_pipe.close unless @error_pipe.closed?
      @response_pipe.close unless @response_pipe.closed?
    end
  end

  sig { returns(IO) }
  def self.forked_child_error_pipe
    UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE")) do |socket|
      receive_forked_child_pipe(socket)
    end
  end

  sig { returns(ForkedChildChannel) }
  def self.forked_child_channel
    UNIXSocketExt.open(ENV.fetch("HOMEBREW_ERROR_PIPE")) do |socket|
      ForkedChildChannel.new(receive_forked_child_pipe(socket), receive_forked_child_pipe(socket))
    end
  end

  sig { params(socket: UNIXSocket).returns(IO) }
  private_class_method def self.receive_forked_child_pipe(socket)
    socket.recv_io.tap do |pipe|
      pipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    end
  end

  sig { params(error: Exception).returns(T::Hash[String, T.untyped]) }
  def self.child_error_hash(error)
    # `rewrite_child_error` and `Cask::Artifact` read these keys back.
    error_hash = {
      "json_class" => error.class.name,
      "m"          => error.message,
      "b"          => error.backtrace,
    }
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

  sig { params(error_pipe: T.nilable(T.any(IO, ForkedChildChannel)), error: Exception).void }
  def self.report_forked_child_error(error_pipe, error)
    require "json"

    coder = JSON::Coder.new do |object|
      case object
      when Exception then child_error_hash(object)
      else object
      end
    end

    error_pipe&.puts coder.dump(error)
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
           child_message_handler: T.nilable(T.proc.params(message: String).returns(T.nilable(String))),
           _blk: T.proc.params(arg0: T.nilable(String)).void).void
  }
  def self.safe_fork(directory: nil, yield_parent: false, child_message_handler: nil, &_blk)
    block = proc do |tmpdir|
      UNIXServerExt.open("#{tmpdir}/socket") do |server|
        error_read, error_write = IO.pipe
        response_read = T.let(nil, T.nilable(IO))
        response_write = T.let(nil, T.nilable(IO))
        response_read, response_write = IO.pipe if child_message_handler

        pid = fork do
          # bootsnap doesn't like these forked processes
          ENV["HOMEBREW_NO_BOOTSNAP"] = "1"
          error_pipe = server.path
          ENV["HOMEBREW_ERROR_PIPE"] = error_pipe
          if child_message_handler
            ENV["HOMEBREW_CHILD_MESSAGE_CHANNEL"] = "1"
          else
            ENV.delete("HOMEBREW_CHILD_MESSAGE_CHANNEL")
          end
          server.close
          error_read.close
          response_write&.close
          error_write.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
          response_read&.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

          yield(error_pipe)
        # This could be any type of exception, so rescue them all.
        rescue Exception => e # rubocop:disable Lint/RescueException
          report_forked_child_error(error_write, e)

          exit!
        else
          exit!(true)
        end

        data = T.let(+"", String)
        reader = Thread.new do
          Thread.current.report_on_exception = false
          # Lines the handler answers are responded to on the response pipe;
          # anything else (e.g. a child error report) stays error data.
          error_read.each_line do |line|
            if child_message_handler && response_write && (response = child_message_handler.call(line))
              response_write.puts response
              response_write.flush
            else
              data << line
            end
          end
        end

        child_reaped = T.let(false, T::Boolean)
        begin
          yield(nil) if yield_parent

          begin
            socket = server.accept_nonblock
          rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
            retry unless Process.waitpid(pid, Process::WNOHANG)

            child_reaped = true
          else
            socket.send_io(error_write)
            socket.send_io(response_read) if response_read
            socket.close
          end
          error_write.close
          response_read&.close
          reader.value
          error_read.close
          response_write&.close
          unless socket.nil?
            Process.waitpid(pid)
            child_reaped = true
          end
        ensure
          # Stop the reader so closing its pipe cannot mask the original exception.
          reader.kill if $ERROR_INFO
          # Close the pipes before reaping: a child blocked waiting for a
          # response must see EOF and exit or `waitpid` would deadlock.
          [error_read, error_write, response_read, response_write].compact.each do |pipe|
            pipe.close unless pipe.closed?
          end
          begin
            Process.waitpid(pid) unless child_reaped
          rescue Errno::ECHILD
            nil
          end
          reader.join
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
