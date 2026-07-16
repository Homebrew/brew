# typed: strict
# frozen_string_literal: true

# An {IO} wrapper class that allows performing non-blocking line reads on the
# provided instance. It is undefined behaviour to run this with other modifying
# {IO} operations, e.g. {IO#read} or {IO#seek}, on the same instance.
class ReadlineNonblock
  BUFFER_SIZE = 4096
  private_constant :BUFFER_SIZE

  sig { params(io: IO).void }
  def initialize(io)
    @io = io
    @buffer = T.let(+"", String)
    @line = T.let(+"", String)
  end

  # Reads and returns a line ending with `"\n"` or remaining text before EOF.
  # Non-blocking reads should return similar output as {IO#readline} with `"\n"`,
  # while reads that would block raise {IO::WaitReadable}.
  #
  # Note that this method does not support the global line separator `$/`.
  # Also it does not modify `$_`.
  #
  # @return the next line
  # @raise [IO::WaitReadable] if read would block
  # @raise [EOFError] on EOF
  sig { returns(String) }
  def read
    begin
      loop do
        if (index = @buffer.index("\n"))
          @line.concat(@buffer.slice!(0..index).to_s)
          break
        end

        @line.concat(@buffer)
        @buffer.clear
        @io.read_nonblock(BUFFER_SIZE, @buffer)
      end
    rescue EOFError
      raise if @line.empty?
    end

    line = @line.freeze
    @line = +""
    line
  end
end
