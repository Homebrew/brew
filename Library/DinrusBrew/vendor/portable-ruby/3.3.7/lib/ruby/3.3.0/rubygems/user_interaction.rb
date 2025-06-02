# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "deprecate"
require_relative "text"

##
# Module that defines the default UserInteraction.  Any class including this
# module will have access to the +ui+ method that returns the default UI.

module Gem::DefaultUserInteraction
  include Gem::Text

  ##
  # The default UI is a class variable of the singleton class for this
  # module.

  @ui = nil

  ##
  # Return the default UI.

  def self.ui
    @ui ||= Gem::ConsoleUI.new
  end

  ##
  # Set the default UI.  If the default UI is never explicitly set, a simple
  # console based UserInteraction will be used automatically.

  def self.ui=(new_ui)
    @ui = new_ui
  end

  ##
  # Use +new_ui+ for the duration of +block+.

  def self.use_ui(new_ui)
    old_ui = @ui
    @ui = new_ui
    yield
  ensure
    @ui = old_ui
  end

  ##
  # See DefaultUserInteraction::ui

  def ui
    Gem::DefaultUserInteraction.ui
  end

  ##
  # See DefaultUserInteraction::ui=

  def ui=(new_ui)
    Gem::DefaultUserInteraction.ui = new_ui
  end

  ##
  # See DefaultUserInteraction::use_ui

  def use_ui(new_ui, &block)
    Gem::DefaultUserInteraction.use_ui(new_ui, &block)
  end
end

##
# UserInteraction allows RubyGems to interact with the user through standard
# methods that can be replaced with more-specific UI methods for different
# displays.
#
# Since UserInteraction dispatches to a concrete UI class you may need to
# reference other classes for specific behavior such as Gem::ConsoleUI or
# Gem::SilentUI.
#
# Example:
#
#   class X
#     include Gem::UserInteraction
#
#     def get_answer
#       n = ask("What is the meaning of life?")
#     end
#   end

module Gem::UserInteraction
  include Gem::DefaultUserInteraction

  ##
  # Displays an alert +statement+.  Asks a +question+ if given.

  def alert(statement, question = nil)
    ui.alert statement, question
  end

  ##
  # Displays an error +statement+ to the error output location.  Asks a
  # +question+ if given.

  def alert_error(statement, question = nil)
    ui.alert_error statement, question
  end

  ##
  # Displays a warning +statement+ to the warning output location.  Asks a
  # +question+ if given.

  def alert_warning(statement, question = nil)
    ui.alert_warning statement, question
  end

  ##
  # Asks a +question+ and returns the answer.

  def ask(question)
    ui.ask question
  end

  ##
  # Asks for a password with a +prompt+

  def ask_for_password(prompt)
    ui.ask_for_password prompt
  end

  ##
  # Asks a yes or no +question+.  Returns true for yes, false for no.

  def ask_yes_no(question, default = nil)
    ui.ask_yes_no question, default
  end

  ##
  # Asks the user to answer +question+ with an answer from the given +list+.

  def choose_from_list(question, list)
    ui.choose_from_list question, list
  end

  ##
  # Displays the given +statement+ on the standard output (or equivalent).

  def say(statement = "")
    ui.say statement
  end

  ##
  # Terminates the RubyGems process with the given +exit_code+

  def terminate_interaction(exit_code = 0)
    ui.terminate_interaction exit_code
  end

  ##
  # Calls +say+ with +msg+ or the results of the block if really_verbose
  # is true.

  def verbose(msg = nil)
    say(clean_text(msg || yield)) if Gem.configuration.really_verbose
  end
end

##
# Gem::StreamUI implements a simple stream based user interface.

class Gem::StreamUI
  extend Gem::Deprecate

  ##
  # The input stream

  attr_reader :ins

  ##
  # The output stream

  attr_reader :outs

  ##
  # The error stream

  attr_reader :errs

  ##
  # Creates a new StreamUI wrapping +in_stream+ for user input, +out_stream+
  # for standard output, +err_stream+ for error output.  If +usetty+ is true
  # then special operations (like asking for passwords) will use the TTY
  # commands to disable character echo.

  def initialize(in_stream, out_stream, err_stream=$stderr, usetty=true)
    @ins = in_stream
    @outs = out_stream
    @errs = err_stream
    @usetty = usetty
  end

  ##
  # Returns true if TTY methods should be used on this StreamUI.

  def tty?
    @usetty && @ins.tty?
  end

  ##
  # Prints a formatted backtrace to the errors stream if backtraces are
  # enabled.

  def backtrace(exception)
    return unless Gem.configuration.backtrace

    @errs.puts "\t#{exception.backtrace.join "\n\t"}"
  end

  ##
  # Choose from a list of options.  +question+ is a prompt displayed above
  # the list.  +list+ is a list of option strings.  Returns the pair
  # [option_name, option_index].

  def choose_from_list(question, list)
    @outs.puts question

    list.each_with_index do |item, index|
      @outs.puts " #{index + 1}. #{item}"
    end

    @outs.print "> "
    @outs.flush

    result = @ins.gets

    return nil, nil unless result

    result = result.strip.to_i - 1
    return nil, nil unless (0...list.size) === result
    [list[result], result]
  end

  ##
  # Ask a question.  Returns a true for yes, false for no.  If not connected
  # to a tty, raises an exception if default is nil, otherwise returns
  # default.

  def ask_yes_no(question, default=nil)
    unless tty?
      if default.nil?
        raise Gem::OperationNotSupportedError,
              "Not connected to a tty and no default specified"
      else
        return default
      end
    end

    default_answer = case default
                     when nil
                       "yn"
                     when true
                       "Yn"
                     else
                       "yN"
    end

    result = nil

    while result.nil? do
      result = case ask "#{question} [#{default_answer}]"
               when /^y/i then true
               when /^n/i then false
               when /^$/  then default
      end
    end

    result
  end

  ##
  # Ask a question.  Returns an answer if connected to a tty, nil otherwise.

  def ask(question)
    return nil unless tty?

    @outs.print(question + "  ")
    @outs.flush

    result = @ins.gets
    result&.chomp!
    result
  end

  ##
  # Ask for a password. Does not echo response to terminal.

  def ask_for_password(question)
    return nil unless tty?

    @outs.print(question, "  ")
    @outs.flush

    password = _gets_noecho
    @outs.puts
    password&.chomp!
    password
  end

  def require_io_console
    @require_io_console ||= begin
      begin
        require "io/console"
      rescue LoadError
      end
      true
    end
  end

  def _gets_noecho
    require_io_console
    @ins.noecho { @ins.gets }
  end

  ##
  # Display a statement.

  def say(statement="")
    @outs.puts statement
  end

  ##
  # Display an informational alert.  Will ask +question+ if it is not nil.

  def alert(statement, question=nil)
    @outs.puts "INFO:  #{statement}"
    ask(question) if question
  end

  ##
  # Display a warning on stderr.  Will ask +question+ if it is not nil.

  def alert_warning(statement, question=nil)
    @errs.puts "WARNING:  #{statement}"
    ask(question) if question
  end

  ##
  # Display an error message in a location expected to get error messages.
  # Will ask +question+ if it is not nil.

  def alert_error(statement, question=nil)
    @errs.puts "ERROR:  #{statement}"
    ask(question) if question
  end

  ##
  # Terminate the application with exit code +status+, running any exit
  # handlers that might have been defined.

  def terminate_interaction(status = 0)
    close
    raise Gem::SystemExitException, status
  end

  def close
  end

  ##
  # Return a progress reporter object chosen from the current verbosity.

  def progress_reporter(*args)
    case Gem.configuration.verbose
    when nil, false
      SilentProgressReporter.new(@outs, *args)
    when true
      SimpleProgressReporter.new(@outs, *args)
    else
      VerboseProgressReporter.new(@outs, *args)
    end
  end

  ##
  # An absolutely silent progress reporter.

  class SilentProgressReporter
    ##
    # The count of items is never updated for the silent progress reporter.

    attr_reader :count

    ##
    # Creates a silent progress reporter that ignores all input arguments.

    def initialize(out_stream, size, initial_message, terminal_message = nil)
    end

    ##
    # Does not print +message+ when updated as this object has taken a vow of
    # silence.

    def updated(message)
    end

    ##
    # Does not print anything when complete as this object has taken a vow of
    # silence.

    def done
    end
  end

  ##
  # A basic dotted progress reporter.

  class SimpleProgressReporter
    include Gem::DefaultUserInteraction

    ##
    # The number of progress items counted so far.

    attr_reader :count

    ##
    # Creates a new progress reporter that will write to +out_stream+ for
    # +size+ items.  Shows the given +initial_message+ when progress starts
    # and the +terminal_message+ when it is complete.

    def initialize(out_stream, size, initial_message, terminal_message = "complete")
      @out = out_stream
      @total = size
      @count = 0
      @terminal_message = terminal_message

      @out.puts initial_message
    end

    ##
    # Prints out a dot and ignores +message+.

    def updated(message)
      @count += 1
      @out.print "."
      @out.flush
    end

    ##
    # Prints out the terminal message.

    def done
      @out.puts "\n#{@terminal_message}"
    end
  end

  ##
  # A progress reporter that prints out messages about the current progress.

  class VerboseProgressReporter
    include Gem::DefaultUserInteraction

    ##
    # The number of progress items counted so far.

    attr_reader :count

    ##
    # Creates a new progress reporter that will write to +out_stream+ for
    # +size+ items.  Shows the given +initial_message+ when progress starts
    # and the +terminal_message+ when it is complete.

    def initialize(out_stream, size, initial_message, terminal_message = "complete")
      @out = out_stream
      @total = size
      @count = 0
      @terminal_message = terminal_message

      @out.puts initial_message
    end

    ##
    # Prints out the position relative to the total and the +message+.

    def updated(message)
      @count += 1
      @out.puts "#{@count}/#{@total}: #{message}"
    end

    ##
    # Prints out the terminal message.

    def done
      @out.puts @terminal_message
    end
  end

  ##
  # Return a download reporter object chosen from the current verbosity

  def download_reporter(*args)
    if [nil, false].include?(Gem.configuration.verbose) || !@outs.tty?
      SilentDownloadReporter.new(@outs, *args)
    else
      ThreadedDownloadReporter.new(@outs, *args)
    end
  end

  ##
  # An absolutely silent download reporter.

  class SilentDownloadReporter
    ##
    # The silent download reporter ignores all arguments

    def initialize(out_stream, *args)
    end

    ##
    # The silent download reporter does not display +filename+ or care about
    # +filesize+ because it is silent.

    def fetch(filename, filesize)
    end

    ##
    # Nothing can update the silent download reporter.

    def update(current)
    end

    ##
    # The silent download reporter won't tell you when the download is done.
    # Because it is silent.

    def done
    end
  end

  ##
  # A progress reporter that behaves nicely with threaded downloading.

  class ThreadedDownloadReporter
    MUTEX = Thread::Mutex.new

    ##
    # The current file name being displayed

    attr_reader :file_name

    ##
    # Creates a new threaded download reporter that will display on
    # +out_stream+.  The other arguments are ignored.

    def initialize(out_stream, *args)
      @file_name = nil
      @out = out_stream
    end

    ##
    # Tells the download reporter that the +file_name+ is being fetched.
    # The other arguments are ignored.

    def fetch(file_name, *args)
      if @file_name.nil?
        @file_name = file_name
        locked_puts "Fetching #{@file_name}"
      end
    end

    ##
    # Updates the threaded download reporter for the given number of +bytes+.

    def update(bytes)
      # Do nothing.
    end

    ##
    # Indicates the download is complete.

    def done
      # Do nothing.
    end

    private

    def locked_puts(message)
      MUTEX.synchronize do
        @out.puts message
      end
    end
  end
end

##
# Subclass of StreamUI that instantiates the user interaction using $stdin,
# $stdout, and $stderr.

class Gem::ConsoleUI < Gem::StreamUI
  ##
  # The Console UI has no arguments as it defaults to reading input from
  # stdin, output to stdout and warnings or errors to stderr.

  def initialize
    super $stdin, $stdout, $stderr, true
  end
end

##
# SilentUI is a UI choice that is absolutely silent.

class Gem::SilentUI < Gem::StreamUI
  ##
  # The SilentUI has no arguments as it does not use any stream.

  def initialize
    io = NullIO.new
    super io, io, io, false
  end

  def close
  end

  def download_reporter(*args) # :nodoc:
    SilentDownloadReporter.new(@outs, *args)
  end

  def progress_reporter(*args) # :nodoc:
    SilentProgressReporter.new(@outs, *args)
  end

  ##
  # An absolutely silent IO.

  class NullIO
    def puts(*args)
    end

    def print(*args)
    end

    def flush
    end

    def gets(*args)
    end

    def tty?
      false
    end
  end
end
