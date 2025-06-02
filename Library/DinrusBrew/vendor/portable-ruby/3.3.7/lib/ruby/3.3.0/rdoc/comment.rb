# frozen_string_literal: true
##
# A comment holds the text comment for a RDoc::CodeObject and provides a
# unified way of cleaning it up and parsing it into an RDoc::Markup::Document.
#
# Each comment may have a different markup format set by #format=.  By default
# 'rdoc' is used.  The :markup: directive tells RDoc which format to use.
#
# See RDoc::MarkupReference@Directive+for+Specifying+RDoc+Source+Format.


class RDoc::Comment

  include RDoc::Text

  ##
  # The format of this comment.  Defaults to RDoc::Markup

  attr_reader :format

  ##
  # The RDoc::TopLevel this comment was found in

  attr_accessor :location

  ##
  # Line where this Comment was written

  attr_accessor :line

  ##
  # For duck-typing when merging classes at load time

  alias file location # :nodoc:

  ##
  # The text for this comment

  attr_reader :text

  ##
  # Alias for text

  alias to_s text

  ##
  # Overrides the content returned by #parse.  Use when there is no #text
  # source for this comment

  attr_writer   :document

  ##
  # Creates a new comment with +text+ that is found in the RDoc::TopLevel
  # +location+.

  def initialize text = nil, location = nil, language = nil
    @location = location
    @text     = text.nil? ? nil : text.dup
    @language = language

    @document   = nil
    @format     = 'rdoc'
    @normalized = false
  end

  ##
  #--
  # TODO deep copy @document

  def initialize_copy copy # :nodoc:
    @text = copy.text.dup
  end

  def == other # :nodoc:
    self.class === other and
      other.text == @text and other.location == @location
  end

  ##
  # Look for a 'call-seq' in the comment to override the normal parameter
  # handling.  The :call-seq: is indented from the baseline.  All lines of the
  # same indentation level and prefix are consumed.
  #
  # For example, all of the following will be used as the :call-seq:
  #
  #   # :call-seq:
  #   #   ARGF.readlines(sep=$/)     -> array
  #   #   ARGF.readlines(limit)      -> array
  #   #   ARGF.readlines(sep, limit) -> array
  #   #
  #   #   ARGF.to_a(sep=$/)     -> array
  #   #   ARGF.to_a(limit)      -> array
  #   #   ARGF.to_a(sep, limit) -> array

  def extract_call_seq method
    # we must handle situations like the above followed by an unindented first
    # comment.  The difficulty is to make sure not to match lines starting
    # with ARGF at the same indent, but that are after the first description
    # paragraph.
    if /^(?<S> ((?!\n)\s)*+        (?# whitespaces except newline))
         :?call-seq:
           (?<B> \g<S>(?<N>\n|\z)  (?# trailing spaces))?
         (?<seq>
           (\g<S>(?!\w)\S.*\g<N>)*
           (?>
             (?<H> \g<S>\w+        (?# ' #   ARGF' in the example above))
             .*\g<N>)?
           (\g<S>\S.*\g<N>         (?# other non-blank line))*+
           (\g<B>+(\k<H>.*\g<N>    (?# ARGF.to_a lines))++)*+
         )
         (?m:^\s*$|\z)
        /x =~ @text
      seq = $~[:seq]

      all_start, all_stop = $~.offset(0)
      @text.slice! all_start...all_stop

      seq.gsub!(/^\s*/, '')
      method.call_seq = seq
    end

    method
  end

  ##
  # A comment is empty if its text String is empty.

  def empty?
    @text.empty?
  end

  ##
  # HACK dubious

  def encode! encoding
    @text = String.new @text, encoding: encoding
    self
  end

  ##
  # Sets the format of this comment and resets any parsed document

  def format= format
    @format = format
    @document = nil
  end

  def inspect # :nodoc:
    location = @location ? @location.relative_name : '(unknown)'

    "#<%s:%x %s %p>" % [self.class, object_id, location, @text]
  end

  ##
  # Normalizes the text.  See RDoc::Text#normalize_comment for details

  def normalize
    return self unless @text
    return self if @normalized # TODO eliminate duplicate normalization

    @text = normalize_comment @text

    @normalized = true

    self
  end

  ##
  # Was this text normalized?

  def normalized? # :nodoc:
    @normalized
  end

  ##
  # Parses the comment into an RDoc::Markup::Document.  The parsed document is
  # cached until the text is changed.

  def parse
    return @document if @document

    @document = super @text, @format
    @document.file = @location
    @document
  end

  ##
  # Removes private sections from this comment.  Private sections are flush to
  # the comment marker and start with <tt>--</tt> and end with <tt>++</tt>.
  # For C-style comments, a private marker may not start at the opening of the
  # comment.
  #
  #   /*
  #    *--
  #    * private
  #    *++
  #    * public
  #    */

  def remove_private
    # Workaround for gsub encoding for Ruby 1.9.2 and earlier
    empty = ''
    empty = RDoc::Encoding.change_encoding empty, @text.encoding

    @text = @text.gsub(%r%^\s*([#*]?)--.*?^\s*(\1)\+\+\n?%m, empty)
    @text = @text.sub(%r%^\s*[#*]?--.*%m, '')
  end

  ##
  # Replaces this comment's text with +text+ and resets the parsed document.
  #
  # An error is raised if the comment contains a document but no text.

  def text= text
    raise RDoc::Error, 'replacing document-only comment is not allowed' if
      @text.nil? and @document

    @document = nil
    @text = text.nil? ? nil : text.dup
  end

  ##
  # Returns true if this comment is in TomDoc format.

  def tomdoc?
    @format == 'tomdoc'
  end

end
