# typed: strict
# frozen_string_literal: true

class IO
  sig { params(sep: String).returns(String) }
  def readline_nonblock(sep = $INPUT_RECORD_SEPARATOR)
    line = +""
    buffer = +""

    begin
      loop do
        break if buffer == sep

        read_nonblock(1, buffer)
        line.concat(buffer)
      end

      line.freeze
    rescue IO::WaitReadable, EOFError
      raise if line.empty?

      line.freeze
    end
  end
end
