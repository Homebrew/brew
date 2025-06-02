require_relative "column_printer"
require_relative "table_printer"
require_relative "wrapped_printer"

class Bundler::Thor
  module Shell
    class Basic
      attr_accessor :base
      attr_reader   :padding

      # Initialize base, mute and padding to nil.
      #
      def initialize #:nodoc:
        @base = nil
        @mute = false
        @padding = 0
        @always_force = false
      end

      # Mute everything that's inside given block
      #
      def mute
        @mute = true
        yield
      ensure
        @mute = false
      end

      # Check if base is muted
      #
      def mute?
        @mute
      end

      # Sets the output padding, not allowing less than zero values.
      #
      def padding=(value)
        @padding = [0, value].max
      end

      # Sets the output padding while executing a block and resets it.
      #
      def indent(count = 1)
        orig_padding = padding
        self.padding = padding + count
        yield
        self.padding = orig_padding
      end

      # Asks something to the user and receives a response.
      #
      # If a default value is specified it will be presented to the user
      # and allows them to select that value with an empty response. This
      # option is ignored when limited answers are supplied.
      #
      # If asked to limit the correct responses, you can pass in an
      # array of acceptable answers.  If one of those is not supplied,
      # they will be shown a message stating that one of those answers
      # must be given and re-asked the question.
      #
      # If asking for sensitive information, the :echo option can be set
      # to false to mask user input from $stdin.
      #
      # If the required input is a path, then set the path option to
      # true. This will enable tab completion for file paths relative
      # to the current working directory on systems that support
      # Readline.
      #
      # ==== Example
      # ask("What is your name?")
      #
      # ask("What is the planet furthest from the sun?", :default => "Pluto")
      #
      # ask("What is your favorite Neopolitan flavor?", :limited_to => ["strawberry", "chocolate", "vanilla"])
      #
      # ask("What is your password?", :echo => false)
      #
      # ask("Where should the file be saved?", :path => true)
      #
      def ask(statement, *args)
        options = args.last.is_a?(Hash) ? args.pop : {}
        color = args.first

        if options[:limited_to]
          ask_filtered(statement, color, options)
        else
          ask_simply(statement, color, options)
        end
      end

      # Say (print) something to the user. If the sentence ends with a whitespace
      # or tab character, a new line is not appended (print + flush). Otherwise
      # are passed straight to puts (behavior got from Highline).
      #
      # ==== Example
      # say("I know you knew that.")
      #
      def say(message = "", color = nil, force_new_line = (message.to_s !~ /( |\t)\Z/))
        return if quiet?

        buffer = prepare_message(message, *color)
        buffer << "\n" if force_new_line && !message.to_s.end_with?("\n")

        stdout.print(buffer)
        stdout.flush
      end

      # Say (print) an error to the user. If the sentence ends with a whitespace
      # or tab character, a new line is not appended (print + flush). Otherwise
      # are passed straight to puts (behavior got from Highline).
      #
      # ==== Example
      # say_error("error: something went wrong")
      #
      def say_error(message = "", color = nil, force_new_line = (message.to_s !~ /( |\t)\Z/))
        return if quiet?

        buffer = prepare_message(message, *color)
        buffer << "\n" if force_new_line && !message.to_s.end_with?("\n")

        stderr.print(buffer)
        stderr.flush
      end

      # Say a status with the given color and appends the message. Since this
      # method is used frequently by actions, it allows nil or false to be given
      # in log_status, avoiding the message from being shown. If a Symbol is
      # given in log_status, it's used as the color.
      #
      def say_status(status, message, log_status = true)
        return if quiet? || log_status == false
        spaces = "  " * (padding + 1)
        status = status.to_s.rjust(12)
        margin = " " * status.length + spaces

        color  = log_status.is_a?(Symbol) ? log_status : :green
        status = set_color status, color, true if color

        message = message.to_s.chomp.gsub(/(?<!\A)^/, margin)
        buffer = "#{status}#{spaces}#{message}\n"

        stdout.print(buffer)
        stdout.flush
      end

      # Make a question the to user and returns true if the user replies "y" or
      # "yes".
      #
      def yes?(statement, color = nil)
        !!(ask(statement, color, add_to_history: false) =~ is?(:yes))
      end

      # Make a question the to user and returns true if the user replies "n" or
      # "no".
      #
      def no?(statement, color = nil)
        !!(ask(statement, color, add_to_history: false) =~ is?(:no))
      end

      # Prints values in columns
      #
      # ==== Parameters
      # Array[String, String, ...]
      #
      def print_in_columns(array)
        printer = ColumnPrinter.new(stdout)
        printer.print(array)
      end

      # Prints a table.
      #
      # ==== Parameters
      # Array[Array[String, String, ...]]
      #
      # ==== Options
      # indent<Integer>:: Indent the first column by indent value.
      # colwidth<Integer>:: Force the first column to colwidth spaces wide.
      # borders<Boolean>:: Adds ascii borders.
      #
      def print_table(array, options = {}) # rubocop:disable Metrics/MethodLength
        printer = TablePrinter.new(stdout, options)
        printer.print(array)
      end

      # Prints a long string, word-wrapping the text to the current width of the
      # terminal display. Ideal for printing heredocs.
      #
      # ==== Parameters
      # String
      #
      # ==== Options
      # indent<Integer>:: Indent each line of the printed paragraph by indent value.
      #
      def print_wrapped(message, options = {})
        printer = WrappedPrinter.new(stdout, options)
        printer.print(message)
      end

      # Deals with file collision and returns true if the file should be
      # overwritten and false otherwise. If a block is given, it uses the block
      # response as the content for the diff.
      #
      # ==== Parameters
      # destination<String>:: the destination file to solve conflicts
      # block<Proc>:: an optional block that returns the value to be used in diff and merge
      #
      def file_collision(destination)
        return true if @always_force
        options = block_given? ? "[Ynaqdhm]" : "[Ynaqh]"

        loop do
          answer = ask(
            %[Overwrite #{destination}? (enter "h" for help) #{options}],
            add_to_history: false
          )

          case answer
          when nil
            say ""
            return true
          when is?(:yes), is?(:force), ""
            return true
          when is?(:no), is?(:skip)
            return false
          when is?(:always)
            return @always_force = true
          when is?(:quit)
            say "Aborting..."
            raise SystemExit
          when is?(:diff)
            show_diff(destination, yield) if block_given?
            say "Retrying..."
          when is?(:merge)
            if block_given? && !merge_tool.empty?
              merge(destination, yield)
              return nil
            end

            say "Please specify merge tool to `THOR_MERGE` env."
          else
            say file_collision_help(block_given?)
          end
        end
      end

      # Called if something goes wrong during the execution. This is used by Bundler::Thor
      # internally and should not be used inside your scripts. If something went
      # wrong, you can always raise an exception. If you raise a Bundler::Thor::Error, it
      # will be rescued and wrapped in the method below.
      #
      def error(statement)
        stderr.puts statement
      end

      # Apply color to the given string with optional bold. Disabled in the
      # Bundler::Thor::Shell::Basic class.
      #
      def set_color(string, *) #:nodoc:
        string
      end

    protected

      def prepare_message(message, *color)
        spaces = "  " * padding
        spaces + set_color(message.to_s, *color)
      end

      def can_display_colors?
        false
      end

      def lookup_color(color)
        return color unless color.is_a?(Symbol)
        self.class.const_get(color.to_s.upcase)
      end

      def stdout
        $stdout
      end

      def stderr
        $stderr
      end

      def is?(value) #:nodoc:
        value = value.to_s

        if value.size == 1
          /\A#{value}\z/i
        else
          /\A(#{value}|#{value[0, 1]})\z/i
        end
      end

      def file_collision_help(block_given) #:nodoc:
        help = <<-HELP
        Y - yes, overwrite
        n - no, do not overwrite
        a - all, overwrite this and all others
        q - quit, abort
        h - help, show this help
        HELP
        if block_given
          help << <<-HELP
        d - diff, show the differences between the old and the new
        m - merge, run merge tool
          HELP
        end
        help
      end

      def show_diff(destination, content) #:nodoc:
        diff_cmd = ENV["THOR_DIFF"] || ENV["RAILS_DIFF"] || "diff -u"

        require "tempfile"
        Tempfile.open(File.basename(destination), File.dirname(destination)) do |temp|
          temp.write content
          temp.rewind
          system %(#{diff_cmd} "#{destination}" "#{temp.path}")
        end
      end

      def quiet? #:nodoc:
        mute? || (base && base.options[:quiet])
      end

      def unix?
        Terminal.unix?
      end

      def ask_simply(statement, color, options)
        default = options[:default]
        message = [statement, ("(#{default})" if default), nil].uniq.join(" ")
        message = prepare_message(message, *color)
        result = Bundler::Thor::LineEditor.readline(message, options)

        return unless result

        result = result.strip

        if default && result == ""
          default
        else
          result
        end
      end

      def ask_filtered(statement, color, options)
        answer_set = options[:limited_to]
        case_insensitive = options.fetch(:case_insensitive, false)
        correct_answer = nil
        until correct_answer
          answers = answer_set.join(", ")
          answer = ask_simply("#{statement} [#{answers}]", color, options)
          correct_answer = answer_match(answer_set, answer, case_insensitive)
          say("Your response must be one of: [#{answers}]. Please try again.") unless correct_answer
        end
        correct_answer
      end

      def answer_match(possibilities, answer, case_insensitive)
        if case_insensitive
          possibilities.detect{ |possibility| possibility.downcase == answer.downcase }
        else
          possibilities.detect{ |possibility| possibility == answer }
        end
      end

      def merge(destination, content) #:nodoc:
        require "tempfile"
        Tempfile.open([File.basename(destination), File.extname(destination)], File.dirname(destination)) do |temp|
          temp.write content
          temp.rewind
          system %(#{merge_tool} "#{temp.path}" "#{destination}")
        end
      end

      def merge_tool #:nodoc:
        @merge_tool ||= ENV["THOR_MERGE"] || git_merge_tool
      end

      def git_merge_tool #:nodoc:
        `git config merge.tool`.rstrip rescue ""
      end
    end
  end
end
