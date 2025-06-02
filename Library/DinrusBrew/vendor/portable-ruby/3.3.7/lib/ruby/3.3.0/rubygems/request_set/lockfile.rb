# frozen_string_literal: true

##
# Parses a gem.deps.rb.lock file and constructs a LockSet containing the
# dependencies found inside.  If the lock file is missing no LockSet is
# constructed.

class Gem::RequestSet::Lockfile
  ##
  # Raised when a lockfile cannot be parsed

  class ParseError < Gem::Exception
    ##
    # The column where the error was encountered

    attr_reader :column

    ##
    # The line where the error was encountered

    attr_reader :line

    ##
    # The location of the lock file

    attr_reader :path

    ##
    # Raises a ParseError with the given +message+ which was encountered at a
    # +line+ and +column+ while parsing.

    def initialize(message, column, line, path)
      @line   = line
      @column = column
      @path   = path
      super "#{message} (at line #{line} column #{column})"
    end
  end

  ##
  # Creates a new Lockfile for the given +request_set+ and +gem_deps_file+
  # location.

  def self.build(request_set, gem_deps_file, dependencies = nil)
    request_set.resolve
    dependencies ||= requests_to_deps request_set.sorted_requests
    new request_set, gem_deps_file, dependencies
  end

  def self.requests_to_deps(requests) # :nodoc:
    deps = {}

    requests.each do |request|
      spec        = request.spec
      name        = request.name
      requirement = request.request.dependency.requirement

      deps[name] = if [Gem::Resolver::VendorSpecification,
                       Gem::Resolver::GitSpecification].include? spec.class
        Gem::Requirement.source_set
      else
        requirement
      end
    end

    deps
  end

  ##
  # The platforms for this Lockfile

  attr_reader :platforms

  def initialize(request_set, gem_deps_file, dependencies)
    @set           = request_set
    @dependencies  = dependencies
    @gem_deps_file = File.expand_path(gem_deps_file)
    @gem_deps_dir  = File.dirname(@gem_deps_file)
    @platforms = []
  end

  def add_DEPENDENCIES(out) # :nodoc:
    out << "DEPENDENCIES"

    out.concat @dependencies.sort.map {|name, requirement|
      "  #{name}#{requirement.for_lockfile}"
    }

    out << nil
  end

  def add_GEM(out, spec_groups) # :nodoc:
    return if spec_groups.empty?

    source_groups = spec_groups.values.flatten.group_by do |request|
      request.spec.source.uri
    end

    source_groups.sort_by {|group,| group.to_s }.map do |group, requests|
      out << "GEM"
      out << "  remote: #{group}"
      out << "  specs:"

      requests.sort_by(&:name).each do |request|
        next if request.spec.name == "bundler"
        platform = "-#{request.spec.platform}" unless
          request.spec.platform == Gem::Platform::RUBY

        out << "    #{request.name} (#{request.version}#{platform})"

        request.full_spec.dependencies.sort.each do |dependency|
          next if dependency.type == :development

          requirement = dependency.requirement
          out << "      #{dependency.name}#{requirement.for_lockfile}"
        end
      end
      out << nil
    end
  end

  def add_GIT(out, git_requests)
    return if git_requests.empty?

    by_repository_revision = git_requests.group_by do |request|
      source = request.spec.source
      [source.repository, source.rev_parse]
    end

    by_repository_revision.each do |(repository, revision), requests|
      out << "GIT"
      out << "  remote: #{repository}"
      out << "  revision: #{revision}"
      out << "  specs:"

      requests.sort_by(&:name).each do |request|
        out << "    #{request.name} (#{request.version})"

        dependencies = request.spec.dependencies.sort_by(&:name)
        dependencies.each do |dep|
          out << "      #{dep.name}#{dep.requirement.for_lockfile}"
        end
      end
      out << nil
    end
  end

  def relative_path_from(dest, base) # :nodoc:
    dest = File.expand_path(dest)
    base = File.expand_path(base)

    if dest.index(base) == 0
      offset = dest[base.size + 1..-1]

      return "." unless offset

      offset
    else
      dest
    end
  end

  def add_PATH(out, path_requests) # :nodoc:
    return if path_requests.empty?

    out << "PATH"
    path_requests.each do |request|
      directory = File.expand_path(request.spec.source.uri)

      out << "  remote: #{relative_path_from directory, @gem_deps_dir}"
      out << "  specs:"
      out << "    #{request.name} (#{request.version})"
    end

    out << nil
  end

  def add_PLATFORMS(out) # :nodoc:
    out << "PLATFORMS"

    platforms = requests.map {|request| request.spec.platform }.uniq

    platforms = platforms.sort_by(&:to_s)

    platforms.each do |platform|
      out << "  #{platform}"
    end

    out << nil
  end

  def spec_groups
    requests.group_by {|request| request.spec.class }
  end

  ##
  # The contents of the lock file.

  def to_s
    out = []

    groups = spec_groups

    add_PATH out, groups.delete(Gem::Resolver::VendorSpecification) { [] }

    add_GIT out, groups.delete(Gem::Resolver::GitSpecification) { [] }

    add_GEM out, groups

    add_PLATFORMS out

    add_DEPENDENCIES out

    out.join "\n"
  end

  ##
  # Writes the lock file alongside the gem dependencies file

  def write
    content = to_s

    File.open "#{@gem_deps_file}.lock", "w" do |io|
      io.write content
    end
  end

  private

  def requests
    @set.sorted_requests
  end
end

require_relative "lockfile/tokenizer"
