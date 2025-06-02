# frozen_string_literal: true
#
# GetoptLong for Ruby
#
# Copyright (C) 1998, 1999, 2000  Motoyuki Kasahara.
#
# You may redistribute and/or modify this library under the same license
# terms as Ruby.
#
# See GetoptLong for documentation.
#
# Additional documents and the latest version of `getoptlong.rb' can be
# found at http://www.sra.co.jp/people/m-kasahr/ruby/getoptlong/

# The GetoptLong class allows you to parse command line options similarly to
# the GNU getopt_long() C library call. Note, however, that GetoptLong is a
# pure Ruby implementation.
#
# GetoptLong allows for POSIX-style options like <tt>--file</tt> as well
# as single letter options like <tt>-f</tt>
#
# The empty option <tt>--</tt> (two minus symbols) is used to end option
# processing. This can be particularly important if options have optional
# arguments.
#
# Here is a simple example of usage:
#
#     require 'getoptlong'
#
#     opts = GetoptLong.new(
#       [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
#       [ '--repeat', '-n', GetoptLong::REQUIRED_ARGUMENT ],
#       [ '--name', GetoptLong::OPTIONAL_ARGUMENT ]
#     )
#
#     dir = nil
#     name = nil
#     repetitions = 1
#     opts.each do |opt, arg|
#       case opt
#         when '--help'
#           puts <<-EOF
#     hello [OPTION] ... DIR
#
#     -h, --help:
#        show help
#
#     --repeat x, -n x:
#        repeat x times
#
#     --name [name]:
#        greet user by name, if name not supplied default is John
#
#     DIR: The directory in which to issue the greeting.
#           EOF
#         when '--repeat'
#           repetitions = arg.to_i
#         when '--name'
#           if arg == ''
#             name = 'John'
#           else
#             name = arg
#           end
#       end
#     end
#
#     if ARGV.length != 1
#       puts "Missing dir argument (try --help)"
#       exit 0
#     end
#
#     dir = ARGV.shift
#
#     Dir.chdir(dir)
#     for i in (1..repetitions)
#       print "Hello"
#       if name
#         print ", #{name}"
#       end
#       puts
#     end
#
# Example command line:
#
#     hello -n 6 --name -- /tmp
#
class GetoptLong
  # Version.
  VERSION = "0.1.1"

  #
  # Orderings.
  #
  ORDERINGS = [REQUIRE_ORDER = 0, PERMUTE = 1, RETURN_IN_ORDER = 2]

  #
  # Argument flags.
  #
  ARGUMENT_FLAGS = [NO_ARGUMENT = 0, REQUIRED_ARGUMENT = 1,
    OPTIONAL_ARGUMENT = 2]

  #
  # Status codes.
  #
  STATUS_YET, STATUS_STARTED, STATUS_TERMINATED = 0, 1, 2

  #
  # Error types.
  #
  class Error  < StandardError; end
  class AmbiguousOption   < Error; end
  class NeedlessArgument < Error; end
  class MissingArgument  < Error; end
  class InvalidOption    < Error; end

  #
  # \Set up option processing.
  #
  # The options to support are passed to new() as an array of arrays.
  # Each sub-array contains any number of String option names which carry
  # the same meaning, and one of the following flags:
  #
  # GetoptLong::NO_ARGUMENT :: Option does not take an argument.
  #
  # GetoptLong::REQUIRED_ARGUMENT :: Option always takes an argument.
  #
  # GetoptLong::OPTIONAL_ARGUMENT :: Option may or may not take an argument.
  #
  # The first option name is considered to be the preferred (canonical) name.
  # Other than that, the elements of each sub-array can be in any order.
  #
  def initialize(*arguments)
    #
    # Current ordering.
    #
    if ENV.include?('POSIXLY_CORRECT')
      @ordering = REQUIRE_ORDER
    else
      @ordering = PERMUTE
    end

    #
    # Hash table of option names.
    # Keys of the table are option names, and their values are canonical
    # names of the options.
    #
    @canonical_names = Hash.new

    #
    # Hash table of argument flags.
    # Keys of the table are option names, and their values are argument
    # flags of the options.
    #
    @argument_flags = Hash.new

    #
    # Whether error messages are output to $stderr.
    #
    @quiet = false

    #
    # Status code.
    #
    @status = STATUS_YET

    #
    # Error code.
    #
    @error = nil

    #
    # Error message.
    #
    @error_message = nil

    #
    # Rest of catenated short options.
    #
    @rest_singles = ''

    #
    # List of non-option-arguments.
    # Append them to ARGV when option processing is terminated.
    #
    @non_option_arguments = Array.new

    if 0 < arguments.length
      set_options(*arguments)
    end
  end

  #
  # \Set the handling of the ordering of options and arguments.
  # A RuntimeError is raised if option processing has already started.
  #
  # The supplied value must be a member of GetoptLong::ORDERINGS. It alters
  # the processing of options as follows:
  #
  # <b>REQUIRE_ORDER</b> :
  #
  # Options are required to occur before non-options.
  #
  # Processing of options ends as soon as a word is encountered that has not
  # been preceded by an appropriate option flag.
  #
  # For example, if -a and -b are options which do not take arguments,
  # parsing command line arguments of '-a one -b two' would result in
  # 'one', '-b', 'two' being left in ARGV, and only ('-a', '') being
  # processed as an option/arg pair.
  #
  # This is the default ordering, if the environment variable
  # POSIXLY_CORRECT is set. (This is for compatibility with GNU getopt_long.)
  #
  # <b>PERMUTE</b> :
  #
  # Options can occur anywhere in the command line parsed. This is the
  # default behavior.
  #
  # Every sequence of words which can be interpreted as an option (with or
  # without argument) is treated as an option; non-option words are skipped.
  #
  # For example, if -a does not require an argument and -b optionally takes
  # an argument, parsing '-a one -b two three' would result in ('-a','') and
  # ('-b', 'two') being processed as option/arg pairs, and 'one','three'
  # being left in ARGV.
  #
  # If the ordering is set to PERMUTE but the environment variable
  # POSIXLY_CORRECT is set, REQUIRE_ORDER is used instead. This is for
  # compatibility with GNU getopt_long.
  #
  # <b>RETURN_IN_ORDER</b> :
  #
  # All words on the command line are processed as options. Words not
  # preceded by a short or long option flag are passed as arguments
  # with an option of '' (empty string).
  #
  # For example, if -a requires an argument but -b does not, a command line
  # of '-a one -b two three' would result in option/arg pairs of ('-a', 'one')
  # ('-b', ''), ('', 'two'), ('', 'three') being processed.
  #
  def ordering=(ordering)
    #
    # The method is failed if option processing has already started.
    #
    if @status != STATUS_YET
      set_error(ArgumentError, "argument error")
      raise RuntimeError,
        "invoke ordering=, but option processing has already started"
    end

    #
    # Check ordering.
    #
    if !ORDERINGS.include?(ordering)
      raise ArgumentError, "invalid ordering `#{ordering}'"
    end
    if ordering == PERMUTE && ENV.include?('POSIXLY_CORRECT')
      @ordering = REQUIRE_ORDER
    else
      @ordering = ordering
    end
  end

  #
  # Return ordering.
  #
  attr_reader :ordering

  #
  # \Set options. Takes the same argument as GetoptLong.new.
  #
  # Raises a RuntimeError if option processing has already started.
  #
  def set_options(*arguments)
    #
    # The method is failed if option processing has already started.
    #
    if @status != STATUS_YET
      raise RuntimeError,
        "invoke set_options, but option processing has already started"
    end

    #
    # Clear tables of option names and argument flags.
    #
    @canonical_names.clear
    @argument_flags.clear

    arguments.each do |arg|
      if !arg.is_a?(Array)
       raise ArgumentError, "the option list contains non-Array argument"
      end

      #
      # Find an argument flag and it set to `argument_flag'.
      #
      argument_flag = nil
      arg.each do |i|
        if ARGUMENT_FLAGS.include?(i)
          if argument_flag != nil
            raise ArgumentError, "too many argument-flags"
          end
          argument_flag = i
        end
      end

      raise ArgumentError, "no argument-flag" if argument_flag == nil

      canonical_name = nil
      arg.each do |i|
        #
        # Check an option name.
        #
        next if i == argument_flag
        begin
          if !i.is_a?(String) || i !~ /\A-([^-]|-.+)\z/
            raise ArgumentError, "an invalid option `#{i}'"
          end
          if (@canonical_names.include?(i))
            raise ArgumentError, "option redefined `#{i}'"
          end
        rescue
          @canonical_names.clear
          @argument_flags.clear
          raise
        end

        #
        # Register the option (`i') to the `@canonical_names' and
        # `@canonical_names' Hashes.
        #
        if canonical_name == nil
          canonical_name = i
        end
        @canonical_names[i] = canonical_name
        @argument_flags[i] = argument_flag
      end
      raise ArgumentError, "no option name" if canonical_name == nil
    end
    return self
  end

  #
  # \Set/Unset `quiet' mode.
  #
  attr_writer :quiet

  #
  # Return the flag of `quiet' mode.
  #
  attr_reader :quiet

  #
  # `quiet?' is an alias of `quiet'.
  #
  alias quiet? quiet

  #
  # Explicitly terminate option processing.
  #
  def terminate
    return nil if @status == STATUS_TERMINATED
    raise RuntimeError, "an error has occurred" if @error != nil

    @status = STATUS_TERMINATED
    @non_option_arguments.reverse_each do |argument|
      ARGV.unshift(argument)
    end

    @canonical_names = nil
    @argument_flags = nil
    @rest_singles = nil
    @non_option_arguments = nil

    return self
  end

  #
  # Returns true if option processing has terminated, false otherwise.
  #
  def terminated?
    return @status == STATUS_TERMINATED
  end

  #
  # \Set an error (a protected method).
  #
  def set_error(type, message)
    $stderr.print("#{$0}: #{message}\n") if !@quiet

    @error = type
    @error_message = message
    @canonical_names = nil
    @argument_flags = nil
    @rest_singles = nil
    @non_option_arguments = nil

    raise type, message
  end
  protected :set_error

  #
  # Examine whether an option processing is failed.
  #
  attr_reader :error

  #
  # `error?' is an alias of `error'.
  #
  alias error? error

  # Return the appropriate error message in POSIX-defined format.
  # If no error has occurred, returns nil.
  #
  def error_message
    return @error_message
  end

  #
  # Get next option name and its argument, as an Array of two elements.
  #
  # The option name is always converted to the first (preferred)
  # name given in the original options to GetoptLong.new.
  #
  # Example: ['--option', 'value']
  #
  # Returns nil if the processing is complete (as determined by
  # STATUS_TERMINATED).
  #
  def get
    option_name, option_argument = nil, ''

    #
    # Check status.
    #
    return nil if @error != nil
    case @status
    when STATUS_YET
      @status = STATUS_STARTED
    when STATUS_TERMINATED
      return nil
    end

    #
    # Get next option argument.
    #
    if 0 < @rest_singles.length
      argument = '-' + @rest_singles
    elsif (ARGV.length == 0)
      terminate
      return nil
    elsif @ordering == PERMUTE
      while 0 < ARGV.length && ARGV[0] !~ /\A-./
        @non_option_arguments.push(ARGV.shift)
      end
      if ARGV.length == 0
        terminate
        return nil
      end
      argument = ARGV.shift
    elsif @ordering == REQUIRE_ORDER
      if (ARGV[0] !~ /\A-./)
        terminate
        return nil
      end
      argument = ARGV.shift
    else
      argument = ARGV.shift
    end

    #
    # Check the special argument `--'.
    # `--' indicates the end of the option list.
    #
    if argument == '--' && @rest_singles.length == 0
      terminate
      return nil
    end

    #
    # Check for long and short options.
    #
    if argument =~ /\A(--[^=]+)/ && @rest_singles.length == 0
      #
      # This is a long style option, which start with `--'.
      #
      pattern = $1
      if @canonical_names.include?(pattern)
        option_name = pattern
      else
        #
        # The option `option_name' is not registered in `@canonical_names'.
        # It may be an abbreviated.
        #
        matches = []
        @canonical_names.each_key do |key|
          if key.index(pattern) == 0
            option_name = key
            matches << key
          end
        end
        if 2 <= matches.length
          set_error(AmbiguousOption, "option `#{argument}' is ambiguous between #{matches.join(', ')}")
        elsif matches.length == 0
          set_error(InvalidOption, "unrecognized option `#{argument}'")
        end
      end

      #
      # Check an argument to the option.
      #
      if @argument_flags[option_name] == REQUIRED_ARGUMENT
        if argument =~ /=(.*)/m
          option_argument = $1
        elsif 0 < ARGV.length
          option_argument = ARGV.shift
        else
          set_error(MissingArgument,
                    "option `#{argument}' requires an argument")
        end
      elsif @argument_flags[option_name] == OPTIONAL_ARGUMENT
        if argument =~ /=(.*)/m
          option_argument = $1
        elsif 0 < ARGV.length && ARGV[0] !~ /\A-./
          option_argument = ARGV.shift
        else
          option_argument = ''
        end
      elsif argument =~ /=(.*)/m
        set_error(NeedlessArgument,
                  "option `#{option_name}' doesn't allow an argument")
      end

    elsif argument =~ /\A(-(.))(.*)/m
      #
      # This is a short style option, which start with `-' (not `--').
      # Short options may be catenated (e.g. `-l -g' is equivalent to
      # `-lg').
      #
      option_name, ch, @rest_singles = $1, $2, $3

      if @canonical_names.include?(option_name)
        #
        # The option `option_name' is found in `@canonical_names'.
        # Check its argument.
        #
        if @argument_flags[option_name] == REQUIRED_ARGUMENT
          if 0 < @rest_singles.length
            option_argument = @rest_singles
            @rest_singles = ''
          elsif 0 < ARGV.length
            option_argument = ARGV.shift
          else
            # 1003.2 specifies the format of this message.
            set_error(MissingArgument, "option requires an argument -- #{ch}")
          end
        elsif @argument_flags[option_name] == OPTIONAL_ARGUMENT
          if 0 < @rest_singles.length
            option_argument = @rest_singles
            @rest_singles = ''
          elsif 0 < ARGV.length && ARGV[0] !~ /\A-./
            option_argument = ARGV.shift
          else
            option_argument = ''
          end
        end
      else
        #
        # This is an invalid option.
        # 1003.2 specifies the format of this message.
        #
        if ENV.include?('POSIXLY_CORRECT')
          set_error(InvalidOption, "invalid option -- #{ch}")
        else
          set_error(InvalidOption, "invalid option -- #{ch}")
        end
      end
    else
      #
      # This is a non-option argument.
      # Only RETURN_IN_ORDER fell into here.
      #
      return '', argument
    end

    return @canonical_names[option_name], option_argument
  end

  #
  # `get_option' is an alias of `get'.
  #
  alias get_option get

  # Iterator version of `get'.
  #
  # The block is called repeatedly with two arguments:
  # The first is the option name.
  # The second is the argument which followed it (if any).
  # Example: ('--opt', 'value')
  #
  # The option name is always converted to the first (preferred)
  # name given in the original options to GetoptLong.new.
  #
  def each
    loop do
      option_name, option_argument = get_option
      break if option_name == nil
      yield option_name, option_argument
    end
  end

  #
  # `each_option' is an alias of `each'.
  #
  alias each_option each
end
