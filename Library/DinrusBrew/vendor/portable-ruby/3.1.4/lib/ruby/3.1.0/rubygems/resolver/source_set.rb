##
# The SourceSet chooses the best available method to query a remote index.
#
# Kind off like BestSet but filters the sources for gems

class Gem::Resolver::SourceSet < Gem::Resolver::Set
  ##
  # Creates a SourceSet for the given +sources+ or Gem::sources if none are
  # specified.  +sources+ must be a Gem::SourceList.

  def initialize
    super()

    @links = {}
    @sets  = {}
  end

  def find_all(req) # :nodoc:
    if set = get_set(req.dependency.name)
      set.find_all req
    else
      []
    end
  end

  # potentially no-op
  def prefetch(reqs) # :nodoc:
    reqs.each do |req|
      if set = get_set(req.dependency.name)
        set.prefetch reqs
      end
    end
  end

  def add_source_gem(name, source)
    @links[name] = source
  end

  private

  def get_set(name)
    link = @links[name]
    @sets[link] ||= Gem::Source.new(link).dependency_resolver_set if link
  end
end
