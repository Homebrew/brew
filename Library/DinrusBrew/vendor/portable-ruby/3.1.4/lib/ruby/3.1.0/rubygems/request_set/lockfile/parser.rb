# frozen_string_literal: true
class Gem::RequestSet::Lockfile::Parser
  ###
  # Parses lockfiles

  def initialize(tokenizer, set, platforms, filename = nil)
    @tokens    = tokenizer
    @filename  = filename
    @set       = set
    @platforms = platforms
  end

  def parse
    until @tokens.empty? do
      token = get

      case token.type
      when :section then
        @tokens.skip :newline

        case token.value
        when "DEPENDENCIES" then
          parse_DEPENDENCIES
        when "GIT" then
          parse_GIT
        when "GEM" then
          parse_GEM
        when "PATH" then
          parse_PATH
        when "PLATFORMS" then
          parse_PLATFORMS
        else
          token = get until @tokens.empty? || peek.first == :section
        end
      else
        raise "BUG: unhandled token #{token.type} (#{token.value.inspect}) at line #{token.line} column #{token.column}"
      end
    end
  end

  ##
  # Gets the next token for a Lockfile

  def get(expected_types = nil, expected_value = nil) # :nodoc:
    token = @tokens.shift

    if expected_types && !Array(expected_types).include?(token.type)
      unget token

      message = "unexpected token [#{token.type.inspect}, #{token.value.inspect}], " +
                "expected #{expected_types.inspect}"

      raise Gem::RequestSet::Lockfile::ParseError.new message, token.column, token.line, @filename
    end

    if expected_value && expected_value != token.value
      unget token

      message = "unexpected token [#{token.type.inspect}, #{token.value.inspect}], " +
                "expected [#{expected_types.inspect}, " +
                "#{expected_value.inspect}]"

      raise Gem::RequestSet::Lockfile::ParseError.new message, token.column, token.line, @filename
    end

    token
  end

  def parse_DEPENDENCIES # :nodoc:
    while !@tokens.empty? && :text == peek.type do
      token = get :text

      requirements = []

      case peek[0]
      when :bang then
        get :bang

        requirements << pinned_requirement(token.value)
      when :l_paren then
        get :l_paren

        loop do
          op      = get(:requirement).value
          version = get(:text).value

          requirements << "#{op} #{version}"

          break unless peek.type == :comma

          get :comma
        end

        get :r_paren

        if peek[0] == :bang
          requirements.clear
          requirements << pinned_requirement(token.value)

          get :bang
        end
      end

      @set.gem token.value, *requirements

      skip :newline
    end
  end

  def parse_GEM # :nodoc:
    sources = []

    while [:entry, "remote"] == peek.first(2) do
      get :entry, "remote"
      data = get(:text).value
      skip :newline

      sources << Gem::Source.new(data)
    end

    sources << Gem::Source.new(Gem::DEFAULT_HOST) if sources.empty?

    get :entry, "specs"

    skip :newline

    set = Gem::Resolver::LockSet.new sources
    last_specs = nil

    while !@tokens.empty? && :text == peek.type do
      token = get :text
      name = token.value
      column = token.column

      case peek[0]
      when :newline then
        last_specs.each do |spec|
          spec.add_dependency Gem::Dependency.new name if column == 6
        end
      when :l_paren then
        get :l_paren

        token = get [:text, :requirement]
        type = token.type
        data = token.value

        if type == :text && column == 4
          version, platform = data.split "-", 2

          platform =
            platform ? Gem::Platform.new(platform) : Gem::Platform::RUBY

          last_specs = set.add name, version, platform
        else
          dependency = parse_dependency name, data

          last_specs.each do |spec|
            spec.add_dependency dependency
          end
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_GIT # :nodoc:
    get :entry, "remote"
    repository = get(:text).value

    skip :newline

    get :entry, "revision"
    revision = get(:text).value

    skip :newline

    type = peek.type
    value = peek.value
    if type == :entry && %w[branch ref tag].include?(value)
      get
      get :text

      skip :newline
    end

    get :entry, "specs"

    skip :newline

    set = Gem::Resolver::GitSet.new
    set.root_dir = @set.install_dir

    last_spec = nil

    while !@tokens.empty? && :text == peek.type do
      token = get :text
      name = token.value
      column = token.column

      case peek[0]
      when :newline then
        last_spec.add_dependency Gem::Dependency.new name if column == 6
      when :l_paren then
        get :l_paren

        token = get [:text, :requirement]
        type = token.type
        data = token.value

        if type == :text && column == 4
          last_spec = set.add_git_spec name, data, repository, revision, true
        else
          dependency = parse_dependency name, data

          last_spec.add_dependency dependency
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_PATH # :nodoc:
    get :entry, "remote"
    directory = get(:text).value

    skip :newline

    get :entry, "specs"

    skip :newline

    set = Gem::Resolver::VendorSet.new
    last_spec = nil

    while !@tokens.empty? && :text == peek.first do
      token = get :text
      name = token.value
      column = token.column

      case peek[0]
      when :newline then
        last_spec.add_dependency Gem::Dependency.new name if column == 6
      when :l_paren then
        get :l_paren

        token = get [:text, :requirement]
        type = token.type
        data = token.value

        if type == :text && column == 4
          last_spec = set.add_vendor_gem name, directory
        else
          dependency = parse_dependency name, data

          last_spec.dependencies << dependency
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_PLATFORMS # :nodoc:
    while !@tokens.empty? && :text == peek.first do
      name = get(:text).value

      @platforms << name

      skip :newline
    end
  end

  ##
  # Parses the requirements following the dependency +name+ and the +op+ for
  # the first token of the requirements and returns a Gem::Dependency object.

  def parse_dependency(name, op) # :nodoc:
    return Gem::Dependency.new name, op unless peek[0] == :text

    version = get(:text).value

    requirements = ["#{op} #{version}"]

    while peek.type == :comma do
      get :comma
      op      = get(:requirement).value
      version = get(:text).value

      requirements << "#{op} #{version}"
    end

    Gem::Dependency.new name, requirements
  end

  private

  def skip(type) # :nodoc:
    @tokens.skip type
  end

  ##
  # Peeks at the next token for Lockfile

  def peek # :nodoc:
    @tokens.peek
  end

  def pinned_requirement(name) # :nodoc:
    requirement = Gem::Dependency.new name
    specification = @set.sets.flat_map do |set|
      set.find_all(requirement)
    end.compact.first

    specification && specification.version
  end

  ##
  # Ungets the last token retrieved by #get

  def unget(token) # :nodoc:
    @tokens.unshift token
  end
end
