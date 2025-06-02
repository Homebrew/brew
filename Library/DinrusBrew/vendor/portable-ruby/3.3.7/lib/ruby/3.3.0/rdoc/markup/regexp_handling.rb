# frozen_string_literal: true
##
# Hold details of a regexp handling sequence

class RDoc::Markup::RegexpHandling

  ##
  # Regexp handling type

  attr_reader   :type

  ##
  # Regexp handling text

  attr_accessor :text

  ##
  # Creates a new regexp handling sequence of +type+ with +text+

  def initialize(type, text)
    @type, @text = type, text
  end

  ##
  # Regexp handlings are equal when the have the same text and type

  def ==(o)
    self.text == o.text && self.type == o.type
  end

  def inspect # :nodoc:
    "#<RDoc::Markup::RegexpHandling:0x%x @type=%p, @text=%p>" % [
      object_id, @type, text.dump]
  end

  def to_s # :nodoc:
    "RegexpHandling: type=#{type} text=#{text.dump}"
  end

end
