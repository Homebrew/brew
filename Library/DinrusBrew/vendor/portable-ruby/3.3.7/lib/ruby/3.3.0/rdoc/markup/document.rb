# frozen_string_literal: true
##
# A Document containing lists, headings, paragraphs, etc.

class RDoc::Markup::Document

  include Enumerable

  ##
  # The file this document was created from.  See also
  # RDoc::ClassModule#add_comment

  attr_reader :file

  ##
  # If a heading is below the given level it will be omitted from the
  # table_of_contents

  attr_accessor :omit_headings_below

  ##
  # The parts of the Document

  attr_reader :parts

  ##
  # Creates a new Document with +parts+

  def initialize *parts
    @parts = []
    @parts.concat parts

    @file = nil
    @omit_headings_from_table_of_contents_below = nil
  end

  ##
  # Appends +part+ to the document

  def << part
    case part
    when RDoc::Markup::Document then
      unless part.empty? then
        parts.concat part.parts
        parts << RDoc::Markup::BlankLine.new
      end
    when String then
      raise ArgumentError,
            "expected RDoc::Markup::Document and friends, got String" unless
        part.empty?
    else
      parts << part
    end
  end

  def == other # :nodoc:
    self.class == other.class and
      @file == other.file and
      @parts == other.parts
  end

  ##
  # Runs this document and all its #items through +visitor+

  def accept visitor
    visitor.start_accepting

    visitor.accept_document self

    visitor.end_accepting
  end

  ##
  # Concatenates the given +parts+ onto the document

  def concat parts
    self.parts.concat parts
  end

  ##
  # Enumerator for the parts of this document

  def each &block
    @parts.each(&block)
  end

  ##
  # Does this document have no parts?

  def empty?
    @parts.empty? or (@parts.length == 1 and merged? and @parts.first.empty?)
  end

  ##
  # The file this Document was created from.

  def file= location
    @file = case location
            when RDoc::TopLevel then
              location.relative_name
            else
              location
            end
  end

  ##
  # When this is a collection of documents (#file is not set and this document
  # contains only other documents as its direct children) #merge replaces
  # documents in this class with documents from +other+ when the file matches
  # and adds documents from +other+ when the files do not.
  #
  # The information in +other+ is preferred over the receiver

  def merge other
    if empty? then
      @parts = other.parts
      return self
    end

    other.parts.each do |other_part|
      self.parts.delete_if do |self_part|
        self_part.file and self_part.file == other_part.file
      end

      self.parts << other_part
    end

    self
  end

  ##
  # Does this Document contain other Documents?

  def merged?
    RDoc::Markup::Document === @parts.first
  end

  def pretty_print q # :nodoc:
    start = @file ? "[doc (#{@file}): " : '[doc: '

    q.group 2, start, ']' do
      q.seplist @parts do |part|
        q.pp part
      end
    end
  end

  ##
  # Appends +parts+ to the document

  def push *parts
    self.parts.concat parts
  end

  ##
  # Returns an Array of headings in the document.
  #
  # Require 'rdoc/markup/formatter' before calling this method.

  def table_of_contents
    accept RDoc::Markup::ToTableOfContents.to_toc
  end

end
