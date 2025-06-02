# frozen_string_literal: true
##
# A hard-break in the middle of a paragraph.

class RDoc::Markup::HardBreak

  @instance = new

  ##
  # RDoc::Markup::HardBreak is a singleton

  def self.new
    @instance
  end

  ##
  # Calls #accept_hard_break on +visitor+

  def accept visitor
    visitor.accept_hard_break self
  end

  def == other # :nodoc:
    self.class === other
  end

  def pretty_print q # :nodoc:
    q.text "[break]"
  end

end

