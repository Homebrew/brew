# frozen-string-literal: true
##
# == Manipulates strings like the UNIX Bourne shell
#
# This module manipulates strings according to the word parsing rules
# of the UNIX Bourne shell.
#
# The shellwords() function was originally a port of shellwords.pl,
# but modified to conform to the Shell & Utilities volume of the IEEE
# Std 1003.1-2008, 2016 Edition [1].
#
# === Usage
#
# You can use Shellwords to parse a string into a Bourne shell friendly Array.
#
#   require 'shellwords'
#
#   argv = Shellwords.split('three blind "mice"')
#   argv #=> ["three", "blind", "mice"]
#
# Once you've required Shellwords, you can use the #split alias
# String#shellsplit.
#
#   argv = "see how they run".shellsplit
#   argv #=> ["see", "how", "they", "run"]
#
# They treat quotes as special characters, so an unmatched quote will
# cause an ArgumentError.
#
#   argv = "they all ran after the farmer's wife".shellsplit
#        #=> ArgumentError: Unmatched quote: ...
#
# Shellwords also provides methods that do the opposite.
# Shellwords.escape, or its alias, String#shellescape, escapes
# shell metacharacters in a string for use in a command line.
#
#   filename = "special's.txt"
#
#   system("cat -- #{filename.shellescape}")
#   # runs "cat -- special\\'s.txt"
#
# Note the '--'.  Without it, cat(1) will treat the following argument
# as a command line option if it starts with '-'.  It is guaranteed
# that Shellwords.escape converts a string to a form that a Bourne
# shell will parse back to the original string, but it is the
# programmer's responsibility to make sure that passing an arbitrary
# argument to a command does no harm.
#
# Shellwords also comes with a core extension for Array, Array#shelljoin.
#
#   dir = "Funny GIFs"
#   argv = %W[ls -lta -- #{dir}]
#   system(argv.shelljoin + " | less")
#   # runs "ls -lta -- Funny\\ GIFs | less"
#
# You can use this method to build a complete command line out of an
# array of arguments.
#
# === Authors
# * Wakou Aoyama
# * Akinori MUSHA <knu@iDaemons.org>
#
# === Contact
# * Akinori MUSHA <knu@iDaemons.org> (current maintainer)
#
# === Resources
#
# 1: {IEEE Std 1003.1-2008, 2016 Edition, the Shell & Utilities volume}[http://pubs.opengroup.org/onlinepubs/9699919799/utilities/contents.html]

module Shellwords
  VERSION = "0.2.0"

  # Splits a string into an array of tokens in the same way the UNIX
  # Bourne shell does.
  #
  #   argv = Shellwords.split('here are "two words"')
  #   argv #=> ["here", "are", "two words"]
  #
  # Note, however, that this is not a command line parser.  Shell
  # metacharacters except for the single and double quotes and
  # backslash are not treated as such.
  #
  #   argv = Shellwords.split('ruby my_prog.rb | less')
  #   argv #=> ["ruby", "my_prog.rb", "|", "less"]
  #
  # String#shellsplit is a shortcut for this function.
  #
  #   argv = 'here are "two words"'.shellsplit
  #   argv #=> ["here", "are", "two words"]
  def shellsplit(line)
    words = []
    field = String.new
    line.scan(/\G\s*(?>([^\s\\\'\"]+)|'([^\']*)'|"((?:[^\"\\]|\\.)*)"|(\\.?)|(\S))(\s|\z)?/m) do
      |word, sq, dq, esc, garbage, sep|
      raise ArgumentError, "Unmatched quote: #{line.inspect}" if garbage
      # 2.2.3 Double-Quotes:
      #
      #   The <backslash> shall retain its special meaning as an
      #   escape character only when followed by one of the following
      #   characters when considered special:
      #
      #   $ ` " \ <newline>
      field << (word || sq || (dq && dq.gsub(/\\([$`"\\\n])/, '\\1')) || esc.gsub(/\\(.)/, '\\1'))
      if sep
        words << field
        field = String.new
      end
    end
    words
  end

  alias shellwords shellsplit

  module_function :shellsplit, :shellwords

  class << self
    alias split shellsplit
  end

  # Escapes a string so that it can be safely used in a Bourne shell
  # command line.  +str+ can be a non-string object that responds to
  # +to_s+.
  #
  # Note that a resulted string should be used unquoted and is not
  # intended for use in double quotes nor in single quotes.
  #
  #   argv = Shellwords.escape("It's better to give than to receive")
  #   argv #=> "It\\'s\\ better\\ to\\ give\\ than\\ to\\ receive"
  #
  # String#shellescape is a shorthand for this function.
  #
  #   argv = "It's better to give than to receive".shellescape
  #   argv #=> "It\\'s\\ better\\ to\\ give\\ than\\ to\\ receive"
  #
  #   # Search files in lib for method definitions
  #   pattern = "^[ \t]*def "
  #   open("| grep -Ern -e #{pattern.shellescape} lib") { |grep|
  #     grep.each_line { |line|
  #       file, lineno, matched_line = line.split(':', 3)
  #       # ...
  #     }
  #   }
  #
  # It is the caller's responsibility to encode the string in the right
  # encoding for the shell environment where this string is used.
  #
  # Multibyte characters are treated as multibyte characters, not as bytes.
  #
  # Returns an empty quoted String if +str+ has a length of zero.
  def shellescape(str)
    str = str.to_s

    # An empty argument will be skipped, so return empty quotes.
    return "''".dup if str.empty?

    str = str.dup

    # Treat multibyte characters as is.  It is the caller's responsibility
    # to encode the string in the right encoding for the shell
    # environment.
    str.gsub!(/[^A-Za-z0-9_\-.,:+\/@\n]/, "\\\\\\&")

    # A LF cannot be escaped with a backslash because a backslash + LF
    # combo is regarded as a line continuation and simply ignored.
    str.gsub!(/\n/, "'\n'")

    return str
  end

  module_function :shellescape

  class << self
    alias escape shellescape
  end

  # Builds a command line string from an argument list, +array+.
  #
  # All elements are joined into a single string with fields separated by a
  # space, where each element is escaped for the Bourne shell and stringified
  # using +to_s+.
  #
  #   ary = ["There's", "a", "time", "and", "place", "for", "everything"]
  #   argv = Shellwords.join(ary)
  #   argv #=> "There\\'s a time and place for everything"
  #
  # Array#shelljoin is a shortcut for this function.
  #
  #   ary = ["Don't", "rock", "the", "boat"]
  #   argv = ary.shelljoin
  #   argv #=> "Don\\'t rock the boat"
  #
  # You can also mix non-string objects in the elements as allowed in Array#join.
  #
  #   output = `#{['ps', '-p', $$].shelljoin}`
  #
  def shelljoin(array)
    array.map { |arg| shellescape(arg) }.join(' ')
  end

  module_function :shelljoin

  class << self
    alias join shelljoin
  end
end

class String
  # call-seq:
  #   str.shellsplit => array
  #
  # Splits +str+ into an array of tokens in the same way the UNIX
  # Bourne shell does.
  #
  # See Shellwords.shellsplit for details.
  def shellsplit
    Shellwords.split(self)
  end

  # call-seq:
  #   str.shellescape => string
  #
  # Escapes +str+ so that it can be safely used in a Bourne shell
  # command line.
  #
  # See Shellwords.shellescape for details.
  def shellescape
    Shellwords.escape(self)
  end
end

class Array
  # call-seq:
  #   array.shelljoin => string
  #
  # Builds a command line string from an argument list +array+ joining
  # all elements escaped for the Bourne shell and separated by a space.
  #
  # See Shellwords.shelljoin for details.
  def shelljoin
    Shellwords.join(self)
  end
end
