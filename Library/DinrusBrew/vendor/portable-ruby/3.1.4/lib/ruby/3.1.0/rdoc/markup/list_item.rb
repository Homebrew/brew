# frozen_string_literal: true
##
# An item within a List that contains paragraphs, headings, etc.
#
# For BULLET, NUMBER, LALPHA and UALPHA lists, the label will always be nil.
# For NOTE and LABEL lists, the list label may contain:
#
# * a single String for a single label
# * an Array of Strings for a list item with multiple terms
# * nil for an extra description attached to a previously labeled list item

class RDoc::Markup::ListItem

  ##
  # The label for the ListItem

  attr_accessor :label

  ##
  # Parts of the ListItem

  attr_reader :parts

  ##
  # Creates a new ListItem with an optional +label+ containing +parts+

  def initialize label = nil, *parts
    @label = label
    @parts = []
    @parts.concat parts
  end

  ##
  # Appends +part+ to the ListItem

  def << part
    @parts << part
  end

  def == other # :nodoc:
    self.class == other.class and
      @label == other.label and
      @parts == other.parts
  end

  ##
  # Runs this list item and all its #parts through +visitor+

  def accept visitor
    visitor.accept_list_item_start self

    @parts.each do |part|
      part.accept visitor
    end

    visitor.accept_list_item_end self
  end

  ##
  # Is the ListItem empty?

  def empty?
    @parts.empty?
  end

  ##
  # Length of parts in the ListItem

  def length
    @parts.length
  end

  def pretty_print q # :nodoc:
    q.group 2, '[item: ', ']' do
      case @label
      when Array then
        q.pp @label
        q.text ';'
        q.breakable
      when String then
        q.pp @label
        q.text ';'
        q.breakable
      end

      q.seplist @parts do |part|
        q.pp part
      end
    end
  end

  ##
  # Adds +parts+ to the ListItem

  def push *parts
    @parts.concat parts
  end

end

