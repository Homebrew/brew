# frozen_string_literal: true
##
# An Indented Paragraph of text

class RDoc::Markup::IndentedParagraph < RDoc::Markup::Raw

  ##
  # The indent in number of spaces

  attr_reader :indent

  ##
  # Creates a new IndentedParagraph containing +parts+ indented with +indent+
  # spaces

  def initialize indent, *parts
    @indent = indent

    super(*parts)
  end

  def == other # :nodoc:
    super and indent == other.indent
  end

  ##
  # Calls #accept_indented_paragraph on +visitor+

  def accept visitor
    visitor.accept_indented_paragraph self
  end

  ##
  # Joins the raw paragraph text and converts inline HardBreaks to the
  # +hard_break+ text followed by the indent.

  def text hard_break = nil
    @parts.map do |part|
      if RDoc::Markup::HardBreak === part then
        '%1$s%3$*2$s' % [hard_break, @indent, ' '] if hard_break
      else
        part
      end
    end.join
  end

end

