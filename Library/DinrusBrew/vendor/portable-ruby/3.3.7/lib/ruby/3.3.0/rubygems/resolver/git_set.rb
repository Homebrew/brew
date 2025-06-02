# frozen_string_literal: true

##
# A GitSet represents gems that are sourced from git repositories.
#
# This is used for gem dependency file support.
#
# Example:
#
#   set = Gem::Resolver::GitSet.new
#   set.add_git_gem 'rake', 'git://example/rake.git', tag: 'rake-10.1.0'

class Gem::Resolver::GitSet < Gem::Resolver::Set
  ##
  # The root directory for git gems in this set.  This is usually Gem.dir, the
  # installation directory for regular gems.

  attr_accessor :root_dir

  ##
  # Contains repositories needing submodules

  attr_reader :need_submodules # :nodoc:

  ##
  # A Hash containing git gem names for keys and a Hash of repository and
  # git commit reference as values.

  attr_reader :repositories # :nodoc:

  ##
  # A hash of gem names to Gem::Resolver::GitSpecifications

  attr_reader :specs # :nodoc:

  def initialize # :nodoc:
    super()

    @git             = ENV["git"] || "git"
    @need_submodules = {}
    @repositories    = {}
    @root_dir        = Gem.dir
    @specs           = {}
  end

  def add_git_gem(name, repository, reference, submodules) # :nodoc:
    @repositories[name] = [repository, reference]
    @need_submodules[repository] = submodules
  end

  ##
  # Adds and returns a GitSpecification with the given +name+ and +version+
  # which came from a +repository+ at the given +reference+.  If +submodules+
  # is true they are checked out along with the repository.
  #
  # This fills in the prefetch information as enough information about the gem
  # is present in the arguments.

  def add_git_spec(name, version, repository, reference, submodules) # :nodoc:
    add_git_gem name, repository, reference, submodules

    source = Gem::Source::Git.new name, repository, reference
    source.root_dir = @root_dir

    spec = Gem::Specification.new do |s|
      s.name    = name
      s.version = version
    end

    git_spec = Gem::Resolver::GitSpecification.new self, spec, source

    @specs[spec.name] = git_spec

    git_spec
  end

  ##
  # Finds all git gems matching +req+

  def find_all(req)
    prefetch nil

    specs.values.select do |spec|
      req.match? spec
    end
  end

  ##
  # Prefetches specifications from the git repositories in this set.

  def prefetch(reqs)
    return unless @specs.empty?

    @repositories.each do |name, (repository, reference)|
      source = Gem::Source::Git.new name, repository, reference
      source.root_dir = @root_dir
      source.remote = @remote

      source.specs.each do |spec|
        git_spec = Gem::Resolver::GitSpecification.new self, spec, source

        @specs[spec.name] = git_spec
      end
    end
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[GitSet", "]" do
      next if @repositories.empty?
      q.breakable

      repos = @repositories.map do |name, (repository, reference)|
        "#{name}: #{repository}@#{reference}"
      end

      q.seplist repos do |repo|
        q.text repo
      end
    end
  end
end
