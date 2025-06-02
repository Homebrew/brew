# frozen_string_literal: true
##
# Inline keeps track of markup and labels to create proper links.

class RDoc::RD::Inline

  ##
  # The text of the reference

  attr_reader :reference

  ##
  # The markup of this reference in RDoc format

  attr_reader :rdoc

  ##
  # Creates a new Inline for +rdoc+ and +reference+.
  #
  # +rdoc+ may be another Inline or a String.  If +reference+ is not given it
  # will use the text from +rdoc+.

  def self.new rdoc, reference = rdoc
    if self === rdoc and reference.equal? rdoc then
      rdoc
    else
      super
    end
  end

  ##
  # Initializes the Inline with +rdoc+ and +inline+

  def initialize rdoc, reference # :not-new:
    @reference = reference.equal?(rdoc) ? reference.dup : reference

    # unpack
    @reference = @reference.reference if self.class === @reference
    @rdoc      = rdoc
  end

  def == other # :nodoc:
    self.class === other and
      @reference == other.reference and @rdoc == other.rdoc
  end

  ##
  # Appends +more+ to this inline.  +more+ may be a String or another Inline.

  def append more
    case more
    when String then
      @reference += more
      @rdoc      += more
    when RDoc::RD::Inline then
      @reference += more.reference
      @rdoc      += more.rdoc
    else
      raise "unknown thingy #{more}"
    end

    self
  end

  def inspect # :nodoc:
    "(inline: #{self})"
  end

  alias to_s rdoc # :nodoc:

end

