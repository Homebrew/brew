# frozen_string_literal: true

##
# A Lock source wraps an installed gem's source and sorts before other sources
# during dependency resolution.  This allows RubyGems to prefer gems from
# dependency lock files.

class Gem::Source::Lock < Gem::Source
  ##
  # The wrapped Gem::Source

  attr_reader :wrapped

  ##
  # Creates a new Lock source that wraps +source+ and moves it earlier in the
  # sort list.

  def initialize(source)
    @wrapped = source
  end

  def <=>(other) # :nodoc:
    case other
    when Gem::Source::Lock then
      @wrapped <=> other.wrapped
    when Gem::Source then
      1
    end
  end

  def ==(other) # :nodoc:
    (self <=> other) == 0
  end

  def hash # :nodoc:
    @wrapped.hash ^ 3
  end

  ##
  # Delegates to the wrapped source's fetch_spec method.

  def fetch_spec(name_tuple)
    @wrapped.fetch_spec name_tuple
  end

  def uri # :nodoc:
    @wrapped.uri
  end
end
