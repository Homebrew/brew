# frozen_string_literal: true

module Prism
  # This represents a source of Ruby code that has been parsed. It is used in
  # conjunction with locations to allow them to resolve line numbers and source
  # ranges.
  class Source
    # The source code that this source object represents.
    attr_reader :source

    # The line number where this source starts.
    attr_accessor :start_line

    # The list of newline byte offsets in the source code.
    attr_reader :offsets

    # Create a new source object with the given source code and newline byte
    # offsets. If no newline byte offsets are given, they will be computed from
    # the source code.
    def initialize(source, start_line = 1, offsets = compute_offsets(source))
      @source = source
      @start_line = start_line
      @offsets = offsets
    end

    # Perform a byteslice on the source code using the given byte offset and
    # byte length.
    def slice(byte_offset, length)
      source.byteslice(byte_offset, length)
    end

    # Binary search through the offsets to find the line number for the given
    # byte offset.
    def line(byte_offset)
      start_line + find_line(byte_offset)
    end

    # Return the byte offset of the start of the line corresponding to the given
    # byte offset.
    def line_start(byte_offset)
      offsets[find_line(byte_offset)]
    end

    # Return the column number for the given byte offset.
    def column(byte_offset)
      byte_offset - line_start(byte_offset)
    end

    # Return the character offset for the given byte offset.
    def character_offset(byte_offset)
      source.byteslice(0, byte_offset).length
    end

    # Return the column number in characters for the given byte offset.
    def character_column(byte_offset)
      character_offset(byte_offset) - character_offset(line_start(byte_offset))
    end

    private

    # Binary search through the offsets to find the line number for the given
    # byte offset.
    def find_line(byte_offset)
      left = 0
      right = offsets.length - 1

      while left <= right
        mid = left + (right - left) / 2
        return mid if offsets[mid] == byte_offset

        if offsets[mid] < byte_offset
          left = mid + 1
        else
          right = mid - 1
        end
      end

      left - 1
    end

    # Find all of the newlines in the source code and return their byte offsets
    # from the start of the string an array.
    def compute_offsets(code)
      offsets = [0]
      code.b.scan("\n") { offsets << $~.end(0) }
      offsets
    end
  end

  # This represents a location in the source.
  class Location
    # A Source object that is used to determine more information from the given
    # offset and length.
    protected attr_reader :source

    # The byte offset from the beginning of the source where this location
    # starts.
    attr_reader :start_offset

    # The length of this location in bytes.
    attr_reader :length

    # The list of comments attached to this location
    attr_reader :comments

    # Create a new location object with the given source, start byte offset, and
    # byte length.
    def initialize(source, start_offset, length)
      @source = source
      @start_offset = start_offset
      @length = length
      @comments = []
    end

    # Create a new location object with the given options.
    def copy(**options)
      Location.new(
        options.fetch(:source) { source },
        options.fetch(:start_offset) { start_offset },
        options.fetch(:length) { length }
      )
    end

    # Returns a string representation of this location.
    def inspect
      "#<Prism::Location @start_offset=#{@start_offset} @length=#{@length} start_line=#{start_line}>"
    end

    # The source code that this location represents.
    def slice
      source.slice(start_offset, length)
    end

    # The character offset from the beginning of the source where this location
    # starts.
    def start_character_offset
      source.character_offset(start_offset)
    end

    # The byte offset from the beginning of the source where this location ends.
    def end_offset
      start_offset + length
    end

    # The character offset from the beginning of the source where this location
    # ends.
    def end_character_offset
      source.character_offset(end_offset)
    end

    # The line number where this location starts.
    def start_line
      source.line(start_offset)
    end

    # The content of the line where this location starts before this location.
    def start_line_slice
      offset = source.line_start(start_offset)
      source.slice(offset, start_offset - offset)
    end

    # The line number where this location ends.
    def end_line
      source.line(end_offset)
    end

    # The column number in bytes where this location starts from the start of
    # the line.
    def start_column
      source.column(start_offset)
    end

    # The column number in characters where this location ends from the start of
    # the line.
    def start_character_column
      source.character_column(start_offset)
    end

    # The column number in bytes where this location ends from the start of the
    # line.
    def end_column
      source.column(end_offset)
    end

    # The column number in characters where this location ends from the start of
    # the line.
    def end_character_column
      source.character_column(end_offset)
    end

    # Implement the hash pattern matching interface for Location.
    def deconstruct_keys(keys)
      { start_offset: start_offset, end_offset: end_offset }
    end

    # Implement the pretty print interface for Location.
    def pretty_print(q)
      q.text("(#{start_line},#{start_column})-(#{end_line},#{end_column})")
    end

    # Returns true if the given other location is equal to this location.
    def ==(other)
      other.is_a?(Location) &&
        other.start_offset == start_offset &&
        other.end_offset == end_offset
    end

    # Returns a new location that stretches from this location to the given
    # other location. Raises an error if this location is not before the other
    # location or if they don't share the same source.
    def join(other)
      raise "Incompatible sources" if source != other.source
      raise "Incompatible locations" if start_offset > other.start_offset

      Location.new(source, start_offset, other.end_offset - start_offset)
    end

    # Returns a null location that does not correspond to a source and points to
    # the beginning of the file. Useful for when you want a location object but
    # do not care where it points.
    def self.null
      new(nil, 0, 0)
    end
  end

  # This represents a comment that was encountered during parsing. It is the
  # base class for all comment types.
  class Comment
    # The location of this comment in the source.
    attr_reader :location

    # Create a new comment object with the given location.
    def initialize(location)
      @location = location
    end

    # Implement the hash pattern matching interface for Comment.
    def deconstruct_keys(keys)
      { location: location }
    end
  end

  # InlineComment objects are the most common. They correspond to comments in
  # the source file like this one that start with #.
  class InlineComment < Comment
    # Returns true if this comment happens on the same line as other code and
    # false if the comment is by itself.
    def trailing?
      !location.start_line_slice.strip.empty?
    end

    # Returns a string representation of this comment.
    def inspect
      "#<Prism::InlineComment @location=#{location.inspect}>"
    end
  end

  # EmbDocComment objects correspond to comments that are surrounded by =begin
  # and =end.
  class EmbDocComment < Comment
    # This can only be true for inline comments.
    def trailing?
      false
    end

    # Returns a string representation of this comment.
    def inspect
      "#<Prism::EmbDocComment @location=#{location.inspect}>"
    end
  end

  # This represents a magic comment that was encountered during parsing.
  class MagicComment
    # A Location object representing the location of the key in the source.
    attr_reader :key_loc

    # A Location object representing the location of the value in the source.
    attr_reader :value_loc

    # Create a new magic comment object with the given key and value locations.
    def initialize(key_loc, value_loc)
      @key_loc = key_loc
      @value_loc = value_loc
    end

    # Returns the key of the magic comment by slicing it from the source code.
    def key
      key_loc.slice
    end

    # Returns the value of the magic comment by slicing it from the source code.
    def value
      value_loc.slice
    end

    # Implement the hash pattern matching interface for MagicComment.
    def deconstruct_keys(keys)
      { key_loc: key_loc, value_loc: value_loc }
    end

    # Returns a string representation of this magic comment.
    def inspect
      "#<Prism::MagicComment @key=#{key.inspect} @value=#{value.inspect}>"
    end
  end

  # This represents an error that was encountered during parsing.
  class ParseError
    # The message associated with this error.
    attr_reader :message

    # A Location object representing the location of this error in the source.
    attr_reader :location

    # Create a new error object with the given message and location.
    def initialize(message, location)
      @message = message
      @location = location
    end

    # Implement the hash pattern matching interface for ParseError.
    def deconstruct_keys(keys)
      { message: message, location: location }
    end

    # Returns a string representation of this error.
    def inspect
      "#<Prism::ParseError @message=#{@message.inspect} @location=#{@location.inspect}>"
    end
  end

  # This represents a warning that was encountered during parsing.
  class ParseWarning
    # The message associated with this warning.
    attr_reader :message

    # A Location object representing the location of this warning in the source.
    attr_reader :location

    # Create a new warning object with the given message and location.
    def initialize(message, location)
      @message = message
      @location = location
    end

    # Implement the hash pattern matching interface for ParseWarning.
    def deconstruct_keys(keys)
      { message: message, location: location }
    end

    # Returns a string representation of this warning.
    def inspect
      "#<Prism::ParseWarning @message=#{@message.inspect} @location=#{@location.inspect}>"
    end
  end

  # This represents the result of a call to ::parse or ::parse_file. It contains
  # the AST, any comments that were encounters, and any errors that were
  # encountered.
  class ParseResult
    # The value that was generated by parsing. Normally this holds the AST, but
    # it can sometimes how a list of tokens or other results passed back from
    # the parser.
    attr_reader :value

    # The list of comments that were encountered during parsing.
    attr_reader :comments

    # The list of magic comments that were encountered during parsing.
    attr_reader :magic_comments

    # An optional location that represents the location of the content after the
    # __END__ marker. This content is loaded into the DATA constant when the
    # file being parsed is the main file being executed.
    attr_reader :data_loc

    # The list of errors that were generated during parsing.
    attr_reader :errors

    # The list of warnings that were generated during parsing.
    attr_reader :warnings

    # A Source instance that represents the source code that was parsed.
    attr_reader :source

    # Create a new parse result object with the given values.
    def initialize(value, comments, magic_comments, data_loc, errors, warnings, source)
      @value = value
      @comments = comments
      @magic_comments = magic_comments
      @data_loc = data_loc
      @errors = errors
      @warnings = warnings
      @source = source
    end

    # Implement the hash pattern matching interface for ParseResult.
    def deconstruct_keys(keys)
      { value: value, comments: comments, magic_comments: magic_comments, data_loc: data_loc, errors: errors, warnings: warnings }
    end

    # Returns true if there were no errors during parsing and false if there
    # were.
    def success?
      errors.empty?
    end

    # Returns true if there were errors during parsing and false if there were
    # not.
    def failure?
      !success?
    end
  end

  # This represents a token from the Ruby source.
  class Token
    # The type of token that this token is.
    attr_reader :type

    # A byteslice of the source that this token represents.
    attr_reader :value

    # A Location object representing the location of this token in the source.
    attr_reader :location

    # Create a new token object with the given type, value, and location.
    def initialize(type, value, location)
      @type = type
      @value = value
      @location = location
    end

    # Implement the hash pattern matching interface for Token.
    def deconstruct_keys(keys)
      { type: type, value: value, location: location }
    end

    # Implement the pretty print interface for Token.
    def pretty_print(q)
      q.group do
        q.text(type.to_s)
        self.location.pretty_print(q)
        q.text("(")
        q.nest(2) do
          q.breakable("")
          q.pp(value)
        end
        q.breakable("")
        q.text(")")
      end
    end

    # Returns true if the given other token is equal to this token.
    def ==(other)
      other.is_a?(Token) &&
        other.type == type &&
        other.value == value
    end
  end
end
