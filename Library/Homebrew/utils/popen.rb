# typed: strict
# frozen_string_literal: true

module Utils
  IO_DEFAULT_BUFFER_SIZE = 4096
  private_constant :IO_DEFAULT_BUFFER_SIZE

  sig {
    type_parameters(:U)
      .params(
        args:    T.nilable(T.any(String, Pathname, T::Hash[String, String])),
        safe:    T::Boolean,
        options: T.nilable(T.any(Pathname, String, Symbol)),
        block:   T.nilable(T.proc.params(arg0: IO).returns(T.type_parameter(:U))),
      ).returns(T.any(T.type_parameter(:U), String))
  }
  def self.popen_read(*args, safe: false, **options, &block)
    output = popen(args, "rb", options, &block)
    return output if !safe || $CHILD_STATUS.success?

    raise ErrorDuringExecution.new(args, status: $CHILD_STATUS, output: [[:stdout, output]])
  end

  sig {
    type_parameters(:U)
      .params(
        args:    T.nilable(T.any(String, Pathname, T::Hash[String, String])),
        options: T.nilable(T.any(Pathname, String, Symbol)),
        block:   T.nilable(T.proc.params(arg0: IO).returns(T.type_parameter(:U))),
      ).returns(T.any(T.type_parameter(:U), String))
  }
  def self.safe_popen_read(*args, **options, &block)
    popen_read(*args, safe: true, **options, &block)
  end

  sig {
    params(
      args:    T.any(String, Pathname),
      safe:    T::Boolean,
      options: T.nilable(T.any(Pathname, String, Symbol)),
      _block:  T.proc.params(arg0: IO).returns(T.anything),
    ).returns(String)
  }
  def self.popen_write(*args, safe: false, **options, &_block)
    output = ""
    popen(args, "w+b", options) do |pipe|
      # Before we yield to the block, capture as much output as we can
      loop do
        output += pipe.read_nonblock(IO_DEFAULT_BUFFER_SIZE)
      rescue IO::WaitReadable, EOFError
        break
      end

      yield pipe
      pipe.close_write
      pipe.wait_readable

      # Capture the rest of the output
      output += pipe.read
      output.freeze
    end
    return output if !safe || $CHILD_STATUS.success?

    raise ErrorDuringExecution.new(args, status: $CHILD_STATUS, output: [[:stdout, output]])
  end

  sig {
    type_parameters(:U)
      .params(
        args:    T.any(String, Pathname),
        options: T.nilable(T.any(Pathname, String, Symbol)),
        block:   T.proc.params(arg0: IO).returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  def self.safe_popen_write(*args, **options, &block)
    popen_write(*args, safe: true, **options, &block)
  end

  sig {
    type_parameters(:U)
      .params(
        args:    T::Array[T.nilable(T.any(Pathname, String, T::Hash[String, String]))],
        mode:    String,
        options: T::Hash[Symbol, T.nilable(T.any(Pathname, String, Symbol))],
        _block:  T.nilable(T.proc.params(arg0: IO).returns(T.type_parameter(:U))),
      ).returns(T.any(T.type_parameter(:U), String))
  }
  def self.popen(args, mode, options = {}, &_block)
    IO.popen("-", mode) do |pipe|
      if pipe
        return pipe.read unless block_given?

        yield pipe
      else
        options[:err] ||= File::NULL unless ENV["HOMEBREW_STDERR"]
        cmd = if args[0].is_a? Hash
          args[1]
        else
          args[0]
        end
        begin
          exec(*args, options)
        rescue Errno::ENOENT
          $stderr.puts "brew: command not found: #{cmd}" if options[:err] != :close
          exit! 127
        rescue SystemCallError
          $stderr.puts "brew: exec failed: #{cmd}" if options[:err] != :close
          exit! 1
        end
      end
    end
  end
end
