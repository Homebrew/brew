# frozen_string_literal: true
##
# An array of attributes which parallels the characters in a string.

class RDoc::Markup::AttrSpan

  ##
  # Creates a new AttrSpan for +length+ characters

  def initialize(length, exclusive)
    @attrs = Array.new(length, 0)
    @exclusive = exclusive
  end

  ##
  # Toggles +bits+ from +start+ to +length+
  def set_attrs(start, length, bits)
    updated = false
    for i in start ... (start+length)
      if (@exclusive & @attrs[i]) == 0 || (@exclusive & bits) != 0
        @attrs[i] |= bits
        updated = true
      end
    end
    updated
  end

  ##
  # Accesses flags for character +n+

  def [](n)
    @attrs[n]
  end

end
