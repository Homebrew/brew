# frozen_string_literal: true
##
# The RequirementList is used to hold the requirements being considered
# while resolving a set of gems.
#
# The RequirementList acts like a queue where the oldest items are removed
# first.

class Gem::Resolver::RequirementList
  include Enumerable

  ##
  # Creates a new RequirementList.

  def initialize
    @exact = []
    @list = []
  end

  def initialize_copy(other) # :nodoc:
    @exact = @exact.dup
    @list = @list.dup
  end

  ##
  # Adds Resolver::DependencyRequest +req+ to this requirements list.

  def add(req)
    if req.requirement.exact?
      @exact.push req
    else
      @list.push req
    end
    req
  end

  ##
  # Enumerates requirements in the list

  def each # :nodoc:
    return enum_for __method__ unless block_given?

    @exact.each do |requirement|
      yield requirement
    end

    @list.each do |requirement|
      yield requirement
    end
  end

  ##
  # How many elements are in the list

  def size
    @exact.size + @list.size
  end

  ##
  # Is the list empty?

  def empty?
    @exact.empty? && @list.empty?
  end

  ##
  # Remove the oldest DependencyRequest from the list.

  def remove
    return @exact.shift unless @exact.empty?
    @list.shift
  end

  ##
  # Returns the oldest five entries from the list.

  def next5
    x = @exact[0,5]
    x + @list[0,5 - x.size]
  end
end
