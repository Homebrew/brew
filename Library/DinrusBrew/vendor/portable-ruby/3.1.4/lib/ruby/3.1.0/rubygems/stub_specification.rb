# frozen_string_literal: true
##
# Gem::StubSpecification reads the stub: line from the gemspec.  This prevents
# us having to eval the entire gemspec in order to find out certain
# information.

class Gem::StubSpecification < Gem::BasicSpecification
  # :nodoc:
  PREFIX = "# stub: ".freeze

  # :nodoc:
  OPEN_MODE = "r:UTF-8:-".freeze

  class StubLine # :nodoc: all
    attr_reader :name, :version, :platform, :require_paths, :extensions,
                :full_name

    NO_EXTENSIONS = [].freeze

    # These are common require paths.
    REQUIRE_PATHS = { # :nodoc:
      "lib"  => "lib".freeze,
      "test" => "test".freeze,
      "ext"  => "ext".freeze,
    }.freeze

    # These are common require path lists.  This hash is used to optimize
    # and consolidate require_path objects.  Most specs just specify "lib"
    # in their require paths, so lets take advantage of that by pre-allocating
    # a require path list for that case.
    REQUIRE_PATH_LIST = { # :nodoc:
      "lib" => ["lib"].freeze,
    }.freeze

    def initialize(data, extensions)
      parts          = data[PREFIX.length..-1].split(" ".freeze, 4)
      @name          = parts[0].freeze
      @version       = if Gem::Version.correct?(parts[1])
        Gem::Version.new(parts[1])
      else
        Gem::Version.new(0)
      end

      @platform      = Gem::Platform.new parts[2]
      @extensions    = extensions
      @full_name     = if platform == Gem::Platform::RUBY
        "#{name}-#{version}"
      else
        "#{name}-#{version}-#{platform}"
      end

      path_list = parts.last
      @require_paths = REQUIRE_PATH_LIST[path_list] || path_list.split("\0".freeze).map! do |x|
        REQUIRE_PATHS[x] || x
      end
    end
  end

  def self.default_gemspec_stub(filename, base_dir, gems_dir)
    new filename, base_dir, gems_dir, true
  end

  def self.gemspec_stub(filename, base_dir, gems_dir)
    new filename, base_dir, gems_dir, false
  end

  attr_reader :base_dir, :gems_dir

  def initialize(filename, base_dir, gems_dir, default_gem)
    super()
    filename.tap(&Gem::UNTAINT)

    self.loaded_from = filename
    @data            = nil
    @name            = nil
    @spec            = nil
    @base_dir        = base_dir
    @gems_dir        = gems_dir
    @default_gem     = default_gem
  end

  ##
  # True when this gem has been activated

  def activated?
    @activated ||=
    begin
      loaded = Gem.loaded_specs[name]
      loaded && loaded.version == version
    end
  end

  def default_gem?
    @default_gem
  end

  def build_extensions # :nodoc:
    return if default_gem?
    return if extensions.empty?

    to_spec.build_extensions
  end

  ##
  # If the gemspec contains a stubline, returns a StubLine instance. Otherwise
  # returns the full Gem::Specification.

  def data
    unless @data
      begin
        saved_lineno = $.

        Gem.open_file loaded_from, OPEN_MODE do |file|
          begin
            file.readline # discard encoding line
            stubline = file.readline.chomp
            if stubline.start_with?(PREFIX)
              extensions = if /\A#{PREFIX}/ =~ file.readline.chomp
                $'.split "\0"
              else
                StubLine::NO_EXTENSIONS
              end

              @data = StubLine.new stubline, extensions
            end
          rescue EOFError
          end
        end
      ensure
        $. = saved_lineno
      end
    end

    @data ||= to_spec
  end

  private :data

  def raw_require_paths # :nodoc:
    data.require_paths
  end

  def missing_extensions?
    return false if default_gem?
    return false if extensions.empty?
    return false if File.exist? gem_build_complete_path

    to_spec.missing_extensions?
  end

  ##
  # Name of the gem

  def name
    data.name
  end

  ##
  # Platform of the gem

  def platform
    data.platform
  end

  ##
  # Extensions for this gem

  def extensions
    data.extensions
  end

  ##
  # Version of the gem

  def version
    data.version
  end

  def full_name
    data.full_name
  end

  ##
  # The full Gem::Specification for this gem, loaded from evalling its gemspec

  def to_spec
    @spec ||= if @data
      loaded = Gem.loaded_specs[name]
      loaded if loaded && loaded.version == version
    end

    @spec ||= Gem::Specification.load(loaded_from)
  end

  ##
  # Is this StubSpecification valid? i.e. have we found a stub line, OR does
  # the filename contain a valid gemspec?

  def valid?
    data
  end

  ##
  # Is there a stub line present for this StubSpecification?

  def stubbed?
    data.is_a? StubLine
  end
end
