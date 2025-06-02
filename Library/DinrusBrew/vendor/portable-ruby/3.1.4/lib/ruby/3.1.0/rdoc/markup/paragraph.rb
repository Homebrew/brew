# frozen_string_literal: true
##
# A Paragraph of text

class RDoc::Markup::Paragraph < RDoc::Markup::Raw

  ##
  # Calls #accept_paragraph on +visitor+

  def accept visitor
    visitor.accept_paragraph self
  end

  ##
  # Joins the raw paragraph text and converts inline HardBreaks to the
  # +hard_break+ text.

  def text hard_break = ''
    @parts.map do |part|
      if RDoc::Markup::HardBreak === part then
        hard_break
      else
        part
      end
    end.join
  end

end

