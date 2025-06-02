# frozen_string_literal: true
#
# GetoptLong for Ruby
#
# Copyright (C) 1998, 1999, 2000  Motoyuki Kasahara.
#
# You may redistribute and/or modify this library under the same license
# terms as Ruby.

# \Class \GetoptLong provides parsing both for options
# and for regular arguments.
#
# Using \GetoptLong, you can define options for your program.
# The program can then capture and respond to whatever options
# are included in the command that executes the program.
#
# A simple example: file <tt>simple.rb</tt>:
#
#   :include: ../sample/getoptlong/simple.rb
#
# If you are somewhat familiar with options,
# you may want to skip to this
# {full example}[#class-GetoptLong-label-Full+Example].
#
# == Options
#
# A \GetoptLong option has:
#
# - A string <em>option name</em>.
# - Zero or more string <em>aliases</em> for the name.
# - An <em>option type</em>.
#
# Options may be defined by calling singleton method GetoptLong.new,
# which returns a new \GetoptLong object.
# Options may then be processed by calling other methods
# such as GetoptLong#each.
#
# === Option Name and Aliases
#
# In the array that defines an option,
# the first element is the string option name.
# Often the name takes the 'long' form, beginning with two hyphens.
#
# The option name may have any number of aliases,
# which are defined by additional string elements.
#
# The name and each alias must be of one of two forms:
#
# - Two hyphens, followed by one or more letters.
# - One hyphen, followed by a single letter.
#
# File <tt>aliases.rb</tt>:
#
#   :include: ../sample/getoptlong/aliases.rb
#
# An option may be cited by its name,
# or by any of its aliases;
# the parsed option always reports the name, not an alias:
#
#   $ ruby aliases.rb -a -p --xxx --aaa -x
#
# Output:
#
#   ["--xxx", ""]
#   ["--xxx", ""]
#   ["--xxx", ""]
#   ["--xxx", ""]
#   ["--xxx", ""]
#
#
# An option may also be cited by an abbreviation of its name or any alias,
# as long as that abbreviation is unique among the options.
#
# File <tt>abbrev.rb</tt>:
#
#   :include: ../sample/getoptlong/abbrev.rb
#
# Command line:
#
#   $ ruby abbrev.rb --xxx --xx --xyz --xy
#
# Output:
#
#   ["--xxx", ""]
#   ["--xxx", ""]
#   ["--xyz", ""]
#   ["--xyz", ""]
#
# This command line raises GetoptLong::AmbiguousOption:
#
#   $ ruby abbrev.rb --x
#
# === Repetition
#
# An option may be cited more than once:
#
#   $ ruby abbrev.rb --xxx --xyz --xxx --xyz
#
# Output:
#
#   ["--xxx", ""]
#   ["--xyz", ""]
#   ["--xxx", ""]
#   ["--xyz", ""]
#
# === Treating Remaining Options as Arguments
#
# A option-like token that appears
# anywhere after the token <tt>--</tt> is treated as an ordinary argument,
# and is not processed as an option:
#
#   $ ruby abbrev.rb --xxx --xyz -- --xxx --xyz
#
# Output:
#
#   ["--xxx", ""]
#   ["--xyz", ""]
#
# === Option Types
#
# Each option definition includes an option type,
# which controls whether the option takes an argument.
#
# File <tt>types.rb</tt>:
#
#   :include: ../sample/getoptlong/types.rb
#
# Note that an option type has to do with the <em>option argument</em>
# (whether it is required, optional, or forbidden),
# not with whether the option itself is required.
#
# ==== Option with Required Argument
#
# An option of type <tt>GetoptLong::REQUIRED_ARGUMENT</tt>
# must be followed by an argument, which is associated with that option:
#
#   $ ruby types.rb --xxx foo
#
# Output:
#
#   ["--xxx", "foo"]
#
# If the option is not last, its argument is whatever follows it
# (even if the argument looks like another option):
#
#   $ ruby types.rb --xxx --yyy
#
# Output:
#
#   ["--xxx", "--yyy"]
#
# If the option is last, an exception is raised:
#
#   $ ruby types.rb
#   # Raises GetoptLong::MissingArgument
#
# ==== Option with Optional Argument
#
# An option of type <tt>GetoptLong::OPTIONAL_ARGUMENT</tt>
# may be followed by an argument, which if given is associated with that option.
#
# If the option is last, it does not have an argument:
#
#   $ ruby types.rb --yyy
#
# Output:
#
#   ["--yyy", ""]
#
# If the option is followed by another option, it does not have an argument:
#
#   $ ruby types.rb --yyy --zzz
#
# Output:
#
#   ["--yyy", ""]
#   ["--zzz", ""]
#
# Otherwise the option is followed by its argument, which is associated
# with that option:
#
#   $ ruby types.rb --yyy foo
#
# Output:
#
#   ["--yyy", "foo"]
#
# ==== Option with No Argument
#
# An option of type <tt>GetoptLong::NO_ARGUMENT</tt> takes no argument:
#
#   ruby types.rb --zzz foo
#
# Output:
#
#   ["--zzz", ""]
#
# === ARGV
#
# You can process options either with method #each and a block,
# or with method #get.
#
# During processing, each found option is removed, along with its argument
# if there is one.
# After processing, each remaining element was neither an option
# nor the argument for an option.
#
# File <tt>argv.rb</tt>:
#
#   :include: ../sample/getoptlong/argv.rb
#
# Command line:
#
#   $ ruby argv.rb --xxx Foo --yyy Bar Baz --zzz Bat Bam
#
# Output:
#
#   Original ARGV: ["--xxx", "Foo", "--yyy", "Bar", "Baz", "--zzz", "Bat", "Bam"]
#   ["--xxx", "Foo"]
#   ["--yyy", "Bar"]
#   ["--zzz", ""]
#   Remaining ARGV: ["Baz", "Bat", "Bam"]
#
# === Ordering
#
# There are three settings that control the way the options
# are interpreted:
#
# - +PERMUTE+.
# - +REQUIRE_ORDER+.
# - +RETURN_IN_ORDER+.
#
# The initial setting for a new \GetoptLong object is +REQUIRE_ORDER+
# if environment variable +POSIXLY_CORRECT+ is defined, +PERMUTE+ otherwise.
#
# ==== PERMUTE Ordering
#
# In the +PERMUTE+ ordering, options and other, non-option,
# arguments may appear in any order and any mixture.
#
# File <tt>permute.rb</tt>:
#
#   :include: ../sample/getoptlong/permute.rb
#
# Command line:
#
#   $ ruby permute.rb Foo --zzz Bar --xxx Baz --yyy Bat Bam --xxx Bag Bah
#
# Output:
#
#   Original ARGV: ["Foo", "--zzz", "Bar", "--xxx", "Baz", "--yyy", "Bat", "Bam", "--xxx", "Bag", "Bah"]
#   ["--zzz", ""]
#   ["--xxx", "Baz"]
#   ["--yyy", "Bat"]
#   ["--xxx", "Bag"]
#   Remaining ARGV: ["Foo", "Bar", "Bam", "Bah"]
#
# ==== REQUIRE_ORDER Ordering
#
# In the +REQUIRE_ORDER+ ordering, all options precede all non-options;
# that is, each word after the first non-option word
# is treated as a non-option word (even if it begins with a hyphen).
#
# File <tt>require_order.rb</tt>:
#
#   :include: ../sample/getoptlong/require_order.rb
#
# Command line:
#
#   $ ruby require_order.rb --xxx Foo Bar --xxx Baz --yyy Bat -zzz
#
# Output:
#
#   Original ARGV: ["--xxx", "Foo", "Bar", "--xxx", "Baz", "--yyy", "Bat", "-zzz"]
#   ["--xxx", "Foo"]
#   Remaining ARGV: ["Bar", "--xxx", "Baz", "--yyy", "Bat", "-zzz"]
#
# ==== RETURN_IN_ORDER Ordering
#
# In the +RETURN_IN_ORDER+ ordering, every word is treated as an option.
# A word that begins with a hyphen (or two) is treated in the usual way;
# a word +word+ that does not so begin is treated as an option
# whose name is an empty string, and whose value is +word+.
#
# File <tt>return_in_order.rb</tt>:
#
#   :include: ../sample/getoptlong/return_in_order.rb
#
# Command line:
#
#   $ ruby return_in_order.rb Foo --xxx Bar Baz --zzz Bat Bam
#
# Output:
#
#   Original ARGV: ["Foo", "--xxx", "Bar", "Baz", "--zzz", "Bat", "Bam"]
#   ["", "Foo"]
#   ["--xxx", "Bar"]
#   ["", "Baz"]
#   ["--zzz", ""]
#   ["", "Bat"]
#   ["", "Bam"]
#   Remaining ARGV: []
#
# === Full Example
#
# File <tt>fibonacci.rb</tt>:
#
#   :include: ../sample/getoptlong/fibonacci.rb
#
# Command line:
#
#   $ ruby fibonacci.rb
#
# Output:
#
#   Option --number is required.
#   Usage:
#
#     -n n, --number n:
#       Compute Fibonacci number for n.
#     -v [boolean], --verbose [boolean]:
#       Show intermediate results; default is 'false'.
#     -h, --help:
#       Show this help.
#
# Command line:
#
#   $ ruby fibonacci.rb --number
#
# Raises GetoptLong::MissingArgument:
#
#   fibonacci.rb: option `--number' requires an argument
#
# Command line:
#
#   $ ruby fibonacci.rb --number 6
#
# Output:
#
#   8
#
# Command line:
#
#   $ ruby fibonacci.rb --number 6 --verbose
#
# Output:
#   1
#   2
#   3
#   5
#   8
#
# Command line:
#
#   $ ruby fibonacci.rb --number 6 --verbose yes
#
# Output:
#
#   --verbose argument must be true or false
#   Usage:
#
#     -n n, --number n:
#       Compute Fibonacci number for n.
#     -v [boolean], --verbose [boolean]:
#       Show intermediate results; default is 'false'.
#     -h, --help:
#       Show this help.
#
class GetoptLong
  # Version.
  VERSION = "0.2.1"

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
  # Returns a new \GetoptLong object based on the given +arguments+.
  # See {Options}[#class-GetoptLong-label-Options].
  #
  # Example:
  #
  #   :include: ../sample/getoptlong/simple.rb
  #
  # Raises an exception if:
  #
  # - Any of +arguments+ is not an array.
  # - Any option name or alias is not a string.
  # - Any option type is invalid.
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

  # Sets the ordering; see {Ordering}[#class-GetoptLong-label-Ordering];
  # returns the new ordering.
  #
  # If the given +ordering+ is +PERMUTE+ and environment variable
  # +POSIXLY_CORRECT+ is defined, sets the ordering to +REQUIRE_ORDER+;
  # otherwise sets the ordering to +ordering+:
  #
  #   options = GetoptLong.new
  #   options.ordering == GetoptLong::PERMUTE # => true
  #   options.ordering = GetoptLong::RETURN_IN_ORDER
  #   options.ordering == GetoptLong::RETURN_IN_ORDER # => true
  #   ENV['POSIXLY_CORRECT'] = 'true'
  #   options.ordering = GetoptLong::PERMUTE
  #   options.ordering == GetoptLong::REQUIRE_ORDER # => true
  #
  # Raises an exception if +ordering+ is invalid.
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
  # Returns the ordering setting.
  #
  attr_reader :ordering

  #
  # Replaces existing options with those given by +arguments+,
  # which have the same form as the arguments to ::new;
  # returns +self+.
  #
  # Raises an exception if option processing has begun.
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
  # Sets quiet mode and returns the given argument:
  #
  # - When +false+ or +nil+, error messages are written to <tt>$stdout</tt>.
  # - Otherwise, error messages are not written.
  #
  attr_writer :quiet

  #
  # Returns the quiet mode setting.
  #
  attr_reader :quiet
  alias quiet? quiet

  #
  # Terminate option processing;
  # returns +nil+ if processing has already terminated;
  # otherwise returns +self+.
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
  # Returns +true+ if option processing has terminated, +false+ otherwise.
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
  # Returns whether option processing has failed.
  #
  attr_reader :error
  alias error? error

  # Return the appropriate error message in POSIX-defined format.
  # If no error has occurred, returns +nil+.
  #
  def error_message
    return @error_message
  end

  #
  # Returns the next option as a 2-element array containing:
  #
  # - The option name (the name itself, not an alias).
  # - The option value.
  #
  # Returns +nil+ if there are no more options.
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
  alias get_option get

  #
  # Calls the given block with each option;
  # each option is a 2-element array containing:
  #
  # - The option name (the name itself, not an alias).
  # - The option value.
  #
  # Example:
  #
  #   :include: ../sample/getoptlong/each.rb
  #
  # Command line:
  #
  #    ruby each.rb -xxx Foo -x Bar --yyy Baz -y Bat --zzz
  #
  # Output:
  #
  #   Original ARGV: ["-xxx", "Foo", "-x", "Bar", "--yyy", "Baz", "-y", "Bat", "--zzz"]
  #   ["--xxx", "xx"]
  #   ["--xxx", "Bar"]
  #   ["--yyy", "Baz"]
  #   ["--yyy", "Bat"]
  #   ["--zzz", ""]
  #   Remaining ARGV: ["Foo"]
  #
  def each
    loop do
      option_name, option_argument = get_option
      break if option_name == nil
      yield option_name, option_argument
    end
  end
  alias each_option each
end
