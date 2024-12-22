# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Utils
  IO_DEFAULT_BUFFER_SIZE = 4096
  private_constant :IO_DEFAULT_BUFFER_SIZE

  def self.popen_read(*args, safe: false, **options, &block)
    output = popen(args, "rb", options, &block)
    return output if !safe || $CHILD_STATUS.success?

    raise ErrorDuringExecution.new(args, status: $CHILD_STATUS, output: [[:stdout, output]])
  end

  def self.safe_popen_read(*args, **options, &block)
    popen_read(*args, safe: true, **options, &block)
  end

  def self.popen_write(*args, safe: false, **options)
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

  def self.safe_popen_write(*args, **options, &block)
    popen_write(*args, safe: true, **options, &block)
  end

  def self.popen(args, mode, options = {})
    IO.popen("-", mode) do |pipe|
      if pipe
        return pipe.read unless block_given?

        yield pipe
      else
        options[:err] ||= File::NULL unless ENV["HOMEBREW_STDERR"]
        begin
          exec(*args, options)
        rescue Errno::ENOENT
          $stderr.puts "brew: command not found: #{args[0]}" if options[:err] != :close
          exit! 127
        rescue SystemCallError
          $stderr.puts "brew: exec failed: #{args[0]}" if options[:err] != :close
          exit! 1
        end
      end
    end
  end
end
