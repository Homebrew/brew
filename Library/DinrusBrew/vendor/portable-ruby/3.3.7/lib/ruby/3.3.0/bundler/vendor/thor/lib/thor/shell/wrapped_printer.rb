require_relative "column_printer"
require_relative "terminal"

class Bundler::Thor
  module Shell
    class WrappedPrinter < ColumnPrinter
      def print(message)
        width = Terminal.terminal_width - @indent
        paras = message.split("\n\n")

        paras.map! do |unwrapped|
          words = unwrapped.split(" ")
          counter = words.first.length
          words.inject do |memo, word|
            word = word.gsub(/\n\005/, "\n").gsub(/\005/, "\n")
            counter = 0 if word.include? "\n"
            if (counter + word.length + 1) < width
              memo = "#{memo} #{word}"
              counter += (word.length + 1)
            else
              memo = "#{memo}\n#{word}"
              counter = word.length
            end
            memo
          end
        end.compact!

        paras.each do |para|
          para.split("\n").each do |line|
            stdout.puts line.insert(0, " " * @indent)
          end
          stdout.puts unless para == paras.last
        end
      end
    end
  end
end

