# typed: strict
# frozen_string_literal: true

class ReadlineNonblock
  sig { params(io: IO).returns(String) }
  def self.read(io)
    line = +""
    buffer = +""

    begin
      loop do
        break if buffer == $INPUT_RECORD_SEPARATOR

        io.read_nonblock(1, buffer)
        line.concat(buffer)
      end

      line.freeze
    rescue IO::WaitReadable, EOFError
      raise if line.empty?

      line.freeze
    end
  end
end
