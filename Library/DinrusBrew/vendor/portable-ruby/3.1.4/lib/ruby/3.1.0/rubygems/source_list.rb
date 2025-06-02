# frozen_string_literal: true

##
# The SourceList represents the sources rubygems has been configured to use.
# A source may be created from an array of sources:
#
#   Gem::SourceList.from %w[https://rubygems.example https://internal.example]
#
# Or by adding them:
#
#   sources = Gem::SourceList.new
#   sources << 'https://rubygems.example'
#
# The most common way to get a SourceList is Gem.sources.

class Gem::SourceList
  include Enumerable

  ##
  # Creates a new SourceList

  def initialize
    @sources = []
  end

  ##
  # The sources in this list

  attr_reader :sources

  ##
  # Creates a new SourceList from an array of sources.

  def self.from(ary)
    list = new

    list.replace ary

    return list
  end

  def initialize_copy(other) # :nodoc:
    @sources = @sources.dup
  end

  ##
  # Appends +obj+ to the source list which may be a Gem::Source, URI or URI
  # String.

  def <<(obj)
    src = case obj
    when Gem::Source
      obj
    else
      Gem::Source.new(obj)
    end

    @sources << src unless @sources.include?(src)
    src
  end

  ##
  # Replaces this SourceList with the sources in +other+  See #<< for
  # acceptable items in +other+.

  def replace(other)
    clear

    other.each do |x|
      self << x
    end

    self
  end

  ##
  # Removes all sources from the SourceList.

  def clear
    @sources.clear
  end

  ##
  # Yields each source URI in the list.

  def each
    @sources.each {|s| yield s.uri.to_s }
  end

  ##
  # Yields each source in the list.

  def each_source(&b)
    @sources.each(&b)
  end

  ##
  # Returns true if there are no sources in this SourceList.

  def empty?
    @sources.empty?
  end

  def ==(other) # :nodoc:
    to_a == other
  end

  ##
  # Returns an Array of source URI Strings.

  def to_a
    @sources.map {|x| x.uri.to_s }
  end

  alias_method :to_ary, :to_a

  ##
  # Returns the first source in the list.

  def first
    @sources.first
  end

  ##
  # Returns true if this source list includes +other+ which may be a
  # Gem::Source or a source URI.

  def include?(other)
    if other.kind_of? Gem::Source
      @sources.include? other
    else
      @sources.find {|x| x.uri.to_s == other.to_s }
    end
  end

  ##
  # Deletes +source+ from the source list which may be a Gem::Source or a URI.

  def delete(source)
    if source.kind_of? Gem::Source
      @sources.delete source
    else
      @sources.delete_if {|x| x.uri.to_s == source.to_s }
    end
  end
end
