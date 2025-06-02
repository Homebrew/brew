# frozen_string_literal: true

##
# The global rubygems pool, available via the rubygems.org API.
# Returns instances of APISpecification.

class Gem::Resolver::APISet < Gem::Resolver::Set
  autoload :GemParser, File.expand_path("api_set/gem_parser", __dir__)

  ##
  # The URI for the dependency API this APISet uses.

  attr_reader :dep_uri # :nodoc:

  ##
  # The Gem::Source that gems are fetched from

  attr_reader :source

  ##
  # The corresponding place to fetch gems.

  attr_reader :uri

  ##
  # Creates a new APISet that will retrieve gems from +uri+ using the RubyGems
  # API URL +dep_uri+ which is described at
  # https://guides.rubygems.org/rubygems-org-api

  def initialize(dep_uri = "https://index.rubygems.org/info/")
    super()

    dep_uri = Gem::URI dep_uri unless Gem::URI === dep_uri

    @dep_uri = dep_uri
    @uri     = dep_uri + ".."

    @data   = Hash.new {|h,k| h[k] = [] }
    @source = Gem::Source.new @uri

    @to_fetch = []
  end

  ##
  # Return an array of APISpecification objects matching
  # DependencyRequest +req+.

  def find_all(req)
    res = []

    return res unless @remote

    if @to_fetch.include?(req.name)
      prefetch_now
    end

    versions(req.name).each do |ver|
      if req.dependency.match? req.name, ver[:number], @prerelease
        res << Gem::Resolver::APISpecification.new(self, ver)
      end
    end

    res
  end

  ##
  # A hint run by the resolver to allow the Set to fetch
  # data for DependencyRequests +reqs+.

  def prefetch(reqs)
    return unless @remote
    names = reqs.map {|r| r.dependency.name }
    needed = names - @data.keys - @to_fetch

    @to_fetch += needed
  end

  def prefetch_now # :nodoc:
    needed = @to_fetch
    @to_fetch = []

    needed.sort.each do |name|
      versions(name)
    end
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[APISet", "]" do
      q.breakable
      q.text "URI: #{@dep_uri}"

      q.breakable
      q.text "gem names:"
      q.pp @data.keys
    end
  end

  ##
  # Return data for all versions of the gem +name+.

  def versions(name) # :nodoc:
    if @data.key?(name)
      return @data[name]
    end

    uri = @dep_uri + name

    begin
      str = Gem::RemoteFetcher.fetcher.fetch_path uri
    rescue Gem::RemoteFetcher::FetchError
      @data[name] = []
    else
      lines(str).each do |ver|
        number, platform, dependencies, requirements = parse_gem(ver)

        platform ||= "ruby"
        dependencies = dependencies.map {|dep_name, reqs| [dep_name, reqs.join(", ")] }
        requirements = requirements.map {|req_name, reqs| [req_name.to_sym, reqs] }.to_h

        @data[name] << { name: name, number: number, platform: platform, dependencies: dependencies, requirements: requirements }
      end
    end

    @data[name]
  end

  private

  def lines(str)
    lines = str.split("\n")
    header = lines.index("---")
    header ? lines[header + 1..-1] : lines
  end

  def parse_gem(string)
    @gem_parser ||= GemParser.new
    @gem_parser.parse(string)
  end
end
