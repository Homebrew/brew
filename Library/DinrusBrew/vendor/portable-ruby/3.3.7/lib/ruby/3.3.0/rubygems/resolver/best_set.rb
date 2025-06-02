# frozen_string_literal: true

##
# The BestSet chooses the best available method to query a remote index.
#
# It combines IndexSet and APISet

class Gem::Resolver::BestSet < Gem::Resolver::ComposedSet
  ##
  # Creates a BestSet for the given +sources+ or Gem::sources if none are
  # specified.  +sources+ must be a Gem::SourceList.

  def initialize(sources = Gem.sources)
    super()

    @sources = sources
  end

  ##
  # Picks which sets to use for the configured sources.

  def pick_sets # :nodoc:
    @sources.each_source do |source|
      @sets << source.dependency_resolver_set
    end
  end

  def find_all(req) # :nodoc:
    pick_sets if @remote && @sets.empty?

    super
  end

  def prefetch(reqs) # :nodoc:
    pick_sets if @remote && @sets.empty?

    super
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[BestSet", "]" do
      q.breakable
      q.text "sets:"

      q.breakable
      q.pp @sets
    end
  end
end
