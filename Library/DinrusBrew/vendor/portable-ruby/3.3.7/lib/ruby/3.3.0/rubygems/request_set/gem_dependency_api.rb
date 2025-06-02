# frozen_string_literal: true

##
# A semi-compatible DSL for the Bundler Gemfile and Isolate gem dependencies
# files.
#
# To work with both the Bundler Gemfile and Isolate formats this
# implementation takes some liberties to allow compatibility with each, most
# notably in #source.
#
# A basic gem dependencies file will look like the following:
#
#   source 'https://rubygems.org'
#
#   gem 'rails', '3.2.14a
#   gem 'devise', '~> 2.1', '>= 2.1.3'
#   gem 'cancan'
#   gem 'airbrake'
#   gem 'pg'
#
# RubyGems recommends saving this as gem.deps.rb over Gemfile or Isolate.
#
# To install the gems in this Gemfile use `gem install -g` to install it and
# create a lockfile.  The lockfile will ensure that when you make changes to
# your gem dependencies file a minimum amount of change is made to the
# dependencies of your gems.
#
# RubyGems can activate all the gems in your dependencies file at startup
# using the RUBYGEMS_GEMDEPS environment variable or through Gem.use_gemdeps.
# See Gem.use_gemdeps for details and warnings.
#
# See `gem help install` and `gem help gem_dependencies` for further details.

class Gem::RequestSet::GemDependencyAPI
  ENGINE_MAP = { # :nodoc:
    jruby: %w[jruby],
    jruby_18: %w[jruby],
    jruby_19: %w[jruby],
    maglev: %w[maglev],
    mri: %w[ruby],
    mri_18: %w[ruby],
    mri_19: %w[ruby],
    mri_20: %w[ruby],
    mri_21: %w[ruby],
    rbx: %w[rbx],
    truffleruby: %w[truffleruby],
    ruby: %w[ruby rbx maglev truffleruby],
    ruby_18: %w[ruby rbx maglev truffleruby],
    ruby_19: %w[ruby rbx maglev truffleruby],
    ruby_20: %w[ruby rbx maglev truffleruby],
    ruby_21: %w[ruby rbx maglev truffleruby],
  }.freeze

  mswin     = Gem::Platform.new "x86-mswin32"
  mswin64   = Gem::Platform.new "x64-mswin64"
  x86_mingw = Gem::Platform.new "x86-mingw32"
  x64_mingw = Gem::Platform.new "x64-mingw32"

  PLATFORM_MAP = { # :nodoc:
    jruby: Gem::Platform::RUBY,
    jruby_18: Gem::Platform::RUBY,
    jruby_19: Gem::Platform::RUBY,
    maglev: Gem::Platform::RUBY,
    mingw: x86_mingw,
    mingw_18: x86_mingw,
    mingw_19: x86_mingw,
    mingw_20: x86_mingw,
    mingw_21: x86_mingw,
    mri: Gem::Platform::RUBY,
    mri_18: Gem::Platform::RUBY,
    mri_19: Gem::Platform::RUBY,
    mri_20: Gem::Platform::RUBY,
    mri_21: Gem::Platform::RUBY,
    mswin: mswin,
    mswin_18: mswin,
    mswin_19: mswin,
    mswin_20: mswin,
    mswin_21: mswin,
    mswin64: mswin64,
    mswin64_19: mswin64,
    mswin64_20: mswin64,
    mswin64_21: mswin64,
    rbx: Gem::Platform::RUBY,
    ruby: Gem::Platform::RUBY,
    ruby_18: Gem::Platform::RUBY,
    ruby_19: Gem::Platform::RUBY,
    ruby_20: Gem::Platform::RUBY,
    ruby_21: Gem::Platform::RUBY,
    truffleruby: Gem::Platform::RUBY,
    x64_mingw: x64_mingw,
    x64_mingw_20: x64_mingw,
    x64_mingw_21: x64_mingw,
  }.freeze

  gt_eq_0        = Gem::Requirement.new ">= 0"
  tilde_gt_1_8_0 = Gem::Requirement.new "~> 1.8.0"
  tilde_gt_1_9_0 = Gem::Requirement.new "~> 1.9.0"
  tilde_gt_2_0_0 = Gem::Requirement.new "~> 2.0.0"
  tilde_gt_2_1_0 = Gem::Requirement.new "~> 2.1.0"

  VERSION_MAP = { # :nodoc:
    jruby: gt_eq_0,
    jruby_18: tilde_gt_1_8_0,
    jruby_19: tilde_gt_1_9_0,
    maglev: gt_eq_0,
    mingw: gt_eq_0,
    mingw_18: tilde_gt_1_8_0,
    mingw_19: tilde_gt_1_9_0,
    mingw_20: tilde_gt_2_0_0,
    mingw_21: tilde_gt_2_1_0,
    mri: gt_eq_0,
    mri_18: tilde_gt_1_8_0,
    mri_19: tilde_gt_1_9_0,
    mri_20: tilde_gt_2_0_0,
    mri_21: tilde_gt_2_1_0,
    mswin: gt_eq_0,
    mswin_18: tilde_gt_1_8_0,
    mswin_19: tilde_gt_1_9_0,
    mswin_20: tilde_gt_2_0_0,
    mswin_21: tilde_gt_2_1_0,
    mswin64: gt_eq_0,
    mswin64_19: tilde_gt_1_9_0,
    mswin64_20: tilde_gt_2_0_0,
    mswin64_21: tilde_gt_2_1_0,
    rbx: gt_eq_0,
    ruby: gt_eq_0,
    ruby_18: tilde_gt_1_8_0,
    ruby_19: tilde_gt_1_9_0,
    ruby_20: tilde_gt_2_0_0,
    ruby_21: tilde_gt_2_1_0,
    truffleruby: gt_eq_0,
    x64_mingw: gt_eq_0,
    x64_mingw_20: tilde_gt_2_0_0,
    x64_mingw_21: tilde_gt_2_1_0,
  }.freeze

  WINDOWS = { # :nodoc:
    mingw: :only,
    mingw_18: :only,
    mingw_19: :only,
    mingw_20: :only,
    mingw_21: :only,
    mri: :never,
    mri_18: :never,
    mri_19: :never,
    mri_20: :never,
    mri_21: :never,
    mswin: :only,
    mswin_18: :only,
    mswin_19: :only,
    mswin_20: :only,
    mswin_21: :only,
    mswin64: :only,
    mswin64_19: :only,
    mswin64_20: :only,
    mswin64_21: :only,
    rbx: :never,
    ruby: :never,
    ruby_18: :never,
    ruby_19: :never,
    ruby_20: :never,
    ruby_21: :never,
    x64_mingw: :only,
    x64_mingw_20: :only,
    x64_mingw_21: :only,
  }.freeze

  ##
  # The gems required by #gem statements in the gem.deps.rb file

  attr_reader :dependencies

  ##
  # A set of gems that are loaded via the +:git+ option to #gem

  attr_reader :git_set # :nodoc:

  ##
  # A Hash containing gem names and files to require from those gems.

  attr_reader :requires

  ##
  # A set of gems that are loaded via the +:path+ option to #gem

  attr_reader :vendor_set # :nodoc:

  ##
  # The groups of gems to exclude from installation

  attr_accessor :without_groups # :nodoc:

  ##
  # Creates a new GemDependencyAPI that will add dependencies to the
  # Gem::RequestSet +set+ based on the dependency API description in +path+.

  def initialize(set, path)
    @set = set
    @path = path

    @current_groups     = nil
    @current_platforms  = nil
    @current_repository = nil
    @dependencies       = {}
    @default_sources    = true
    @git_set            = @set.git_set
    @git_sources        = {}
    @installing         = false
    @requires           = Hash.new {|h, name| h[name] = [] }
    @vendor_set         = @set.vendor_set
    @source_set         = @set.source_set
    @gem_sources        = {}
    @without_groups     = []

    git_source :github do |repo_name|
      repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include? "/"

      "https://github.com/#{repo_name}.git"
    end

    git_source :bitbucket do |repo_name|
      repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include? "/"

      user, = repo_name.split "/", 2

      "https://#{user}@bitbucket.org/#{repo_name}.git"
    end
  end

  ##
  # Adds +dependencies+ to the request set if any of the +groups+ are allowed.
  # This is used for gemspec dependencies.

  def add_dependencies(groups, dependencies) # :nodoc:
    return unless (groups & @without_groups).empty?

    dependencies.each do |dep|
      @set.gem dep.name, *dep.requirement.as_list
    end
  end

  private :add_dependencies

  ##
  # Finds a gemspec with the given +name+ that lives at +path+.

  def find_gemspec(name, path) # :nodoc:
    glob = File.join path, "#{name}.gemspec"

    spec_files = Dir[glob]

    case spec_files.length
    when 1 then
      spec_file = spec_files.first

      spec = Gem::Specification.load spec_file

      return spec if spec

      raise ArgumentError, "invalid gemspec #{spec_file}"
    when 0 then
      raise ArgumentError, "no gemspecs found at #{Dir.pwd}"
    else
      raise ArgumentError,
        "found multiple gemspecs at #{Dir.pwd}, " \
        "use the name: option to specify the one you want"
    end
  end

  ##
  # Changes the behavior of gem dependency file loading to installing mode.
  # In installing mode certain restrictions are ignored such as ruby version
  # mismatch checks.

  def installing=(installing) # :nodoc:
    @installing = installing
  end

  ##
  # Loads the gem dependency file and returns self.

  def load
    instance_eval File.read(@path), @path, 1

    self
  end

  ##
  # :category: Gem Dependencies DSL
  #
  # :call-seq:
  #   gem(name)
  #   gem(name, *requirements)
  #   gem(name, *requirements, options)
  #
  # Specifies a gem dependency with the given +name+ and +requirements+.  You
  # may also supply +options+ following the +requirements+
  #
  # +options+ include:
  #
  # require: ::
  #   RubyGems does not provide any autorequire features so requires in a gem
  #   dependencies file are recorded but ignored.
  #
  #   In bundler the require: option overrides the file to require during
  #   Bundler.require.  By default the name of the dependency is required in
  #   Bundler.  A single file or an Array of files may be given.
  #
  #   To disable requiring any file give +false+:
  #
  #     gem 'rake', require: false
  #
  # group: ::
  #   Place the dependencies in the given dependency group.  A single group or
  #   an Array of groups may be given.
  #
  #   See also #group
  #
  # platform: ::
  #   Only install the dependency on the given platform.  A single platform or
  #   an Array of platforms may be given.
  #
  #   See #platform for a list of platforms available.
  #
  # path: ::
  #   Install this dependency from an unpacked gem in the given directory.
  #
  #     gem 'modified_gem', path: 'vendor/modified_gem'
  #
  # git: ::
  #   Install this dependency from a git repository:
  #
  #     gem 'private_gem', git: git@my.company.example:private_gem.git'
  #
  # gist: ::
  #   Install this dependency from the gist ID:
  #
  #     gem 'bang', gist: '1232884'
  #
  # github: ::
  #   Install this dependency from a github git repository:
  #
  #     gem 'private_gem', github: 'my_company/private_gem'
  #
  # submodules: ::
  #   Set to +true+ to include submodules when fetching the git repository for
  #   git:, gist: and github: dependencies.
  #
  # ref: ::
  #   Use the given commit name or SHA for git:, gist: and github:
  #   dependencies.
  #
  # branch: ::
  #   Use the given branch for git:, gist: and github: dependencies.
  #
  # tag: ::
  #   Use the given tag for git:, gist: and github: dependencies.

  def gem(name, *requirements)
    options = requirements.pop if requirements.last.is_a?(Hash)
    options ||= {}

    options[:git] = @current_repository if @current_repository

    source_set = false

    source_set ||= gem_path       name, options
    source_set ||= gem_git        name, options
    source_set ||= gem_git_source name, options
    source_set ||= gem_source     name, options

    duplicate = @dependencies.include? name

    @dependencies[name] =
      if requirements.empty? && !source_set
        Gem::Requirement.default
      elsif source_set
        Gem::Requirement.source_set
      else
        Gem::Requirement.create requirements
      end

    return unless gem_platforms name, options

    groups = gem_group name, options

    return unless (groups & @without_groups).empty?

    pin_gem_source name, :default unless source_set

    gem_requires name, options

    if duplicate
      warn <<-WARNING
Gem dependencies file #{@path} requires #{name} more than once.
      WARNING
    end

    @set.gem name, *requirements
  end

  ##
  # Handles the git: option from +options+ for gem +name+.
  #
  # Returns +true+ if the gist or git option was handled.

  def gem_git(name, options) # :nodoc:
    if gist = options.delete(:gist)
      options[:git] = "https://gist.github.com/#{gist}.git"
    end

    return unless repository = options.delete(:git)

    pin_gem_source name, :git, repository

    reference = gem_git_reference options

    submodules = options.delete :submodules

    @git_set.add_git_gem name, repository, reference, submodules

    true
  end

  ##
  # Handles the git options from +options+ for git gem.
  #
  # Returns reference for the git gem.

  def gem_git_reference(options) # :nodoc:
    ref    = options.delete :ref
    branch = options.delete :branch
    tag    = options.delete :tag

    reference = nil
    reference ||= ref
    reference ||= branch
    reference ||= tag

    if ref && branch
      warn <<-WARNING
Gem dependencies file #{@path} includes git reference for both ref and branch but only ref is used.
      WARNING
    end
    if (ref || branch) && tag
      warn <<-WARNING
Gem dependencies file #{@path} includes git reference for both ref/branch and tag but only ref/branch is used.
      WARNING
    end

    reference
  end

  private :gem_git

  ##
  # Handles a git gem option from +options+ for gem +name+ for a git source
  # registered through git_source.
  #
  # Returns +true+ if the custom source option was handled.

  def gem_git_source(name, options) # :nodoc:
    return unless git_source = (@git_sources.keys & options.keys).last

    source_callback = @git_sources[git_source]
    source_param = options.delete git_source

    git_url = source_callback.call source_param

    options[:git] = git_url

    gem_git name, options

    true
  end

  private :gem_git_source

  ##
  # Handles the :group and :groups +options+ for the gem with the given
  # +name+.

  def gem_group(name, options) # :nodoc:
    g = options.delete :group
    all_groups = g ? Array(g) : []

    groups = options.delete :groups
    all_groups |= groups if groups

    all_groups |= @current_groups if @current_groups

    all_groups
  end

  private :gem_group

  ##
  # Handles the path: option from +options+ for gem +name+.
  #
  # Returns +true+ if the path option was handled.

  def gem_path(name, options) # :nodoc:
    return unless directory = options.delete(:path)

    pin_gem_source name, :path, directory

    @vendor_set.add_vendor_gem name, directory

    true
  end

  private :gem_path

  ##
  # Handles the source: option from +options+ for gem +name+.
  #
  # Returns +true+ if the source option was handled.

  def gem_source(name, options) # :nodoc:
    return unless source = options.delete(:source)

    pin_gem_source name, :source, source

    @source_set.add_source_gem name, source

    true
  end

  private :gem_source

  ##
  # Handles the platforms: option from +options+.  Returns true if the
  # platform matches the current platform.

  def gem_platforms(name, options) # :nodoc:
    platform_names = Array(options.delete(:platform))
    platform_names.concat Array(options.delete(:platforms))
    platform_names.concat @current_platforms if @current_platforms

    return true if platform_names.empty?

    platform_names.any? do |platform_name|
      raise ArgumentError, "unknown platform #{platform_name.inspect}" unless
        platform = PLATFORM_MAP[platform_name]

      next false unless Gem::Platform.match_gem? platform, name

      if engines = ENGINE_MAP[platform_name]
        next false unless engines.include? Gem.ruby_engine
      end

      case WINDOWS[platform_name]
      when :only then
        next false unless Gem.win_platform?
      when :never then
        next false if Gem.win_platform?
      end

      VERSION_MAP[platform_name].satisfied_by? Gem.ruby_version
    end
  end

  private :gem_platforms

  ##
  # Records the require: option from +options+ and adds those files, or the
  # default file to the require list for +name+.

  def gem_requires(name, options) # :nodoc:
    if options.include? :require
      if requires = options.delete(:require)
        @requires[name].concat Array requires
      end
    else
      @requires[name] << name
    end
    raise ArgumentError, "Unhandled gem options #{options.inspect}" unless options.empty?
  end

  private :gem_requires

  ##
  # :category: Gem Dependencies DSL
  #
  # Block form for specifying gems from a git +repository+.
  #
  #   git 'https://github.com/rails/rails.git' do
  #     gem 'activesupport'
  #     gem 'activerecord'
  #   end

  def git(repository)
    @current_repository = repository

    yield
  ensure
    @current_repository = nil
  end

  ##
  # Defines a custom git source that uses +name+ to expand git repositories
  # for use in gems built from git repositories.  You must provide a block
  # that accepts a git repository name for expansion.

  def git_source(name, &callback)
    @git_sources[name] = callback
  end

  ##
  # Returns the basename of the file the dependencies were loaded from

  def gem_deps_file # :nodoc:
    File.basename @path
  end

  ##
  # :category: Gem Dependencies DSL
  #
  # Loads dependencies from a gemspec file.
  #
  # +options+ include:
  #
  # name: ::
  #   The name portion of the gemspec file.  Defaults to searching for any
  #   gemspec file in the current directory.
  #
  #     gemspec name: 'my_gem'
  #
  # path: ::
  #   The path the gemspec lives in.  Defaults to the current directory:
  #
  #     gemspec 'my_gem', path: 'gemspecs', name: 'my_gem'
  #
  # development_group: ::
  #   The group to add development dependencies to.  By default this is
  #   :development.  Only one group may be specified.

  def gemspec(options = {})
    name              = options.delete(:name) || "{,*}"
    path              = options.delete(:path) || "."
    development_group = options.delete(:development_group) || :development

    spec = find_gemspec name, path

    groups = gem_group spec.name, {}

    self_dep = Gem::Dependency.new spec.name, spec.version

    add_dependencies groups, [self_dep]
    add_dependencies groups, spec.runtime_dependencies

    @dependencies[spec.name] = Gem::Requirement.source_set

    spec.dependencies.each do |dep|
      @dependencies[dep.name] = dep.requirement
    end

    groups << development_group

    add_dependencies groups, spec.development_dependencies

    @vendor_set.add_vendor_gem spec.name, path
    gem_requires spec.name, options
  end

  ##
  # :category: Gem Dependencies DSL
  #
  # Block form for placing a dependency in the given +groups+.
  #
  #   group :development do
  #     gem 'debugger'
  #   end
  #
  #   group :development, :test do
  #     gem 'minitest'
  #   end
  #
  # Groups can be excluded at install time using `gem install -g --without
  # development`.  See `gem help install` and `gem help gem_dependencies` for
  # further details.

  def group(*groups)
    @current_groups = groups

    yield
  ensure
    @current_groups = nil
  end

  ##
  # Pins the gem +name+ to the given +source+.  Adding a gem with the same
  # name from a different +source+ will raise an exception.

  def pin_gem_source(name, type = :default, source = nil)
    source_description =
      case type
      when :default then "(default)"
      when :path    then "path: #{source}"
      when :git     then "git: #{source}"
      when :source  then "source: #{source}"
      else               "(unknown)"
      end

    raise ArgumentError,
      "duplicate source #{source_description} for gem #{name}" if
        @gem_sources.fetch(name, source) != source

    @gem_sources[name] = source
  end

  private :pin_gem_source

  ##
  # :category: Gem Dependencies DSL
  #
  # Block form for restricting gems to a set of platforms.
  #
  # The gem dependencies platform is different from Gem::Platform.  A platform
  # gem.deps.rb platform matches on the ruby engine, the ruby version and
  # whether or not windows is allowed.
  #
  # :ruby, :ruby_XY ::
  #   Matches non-windows, non-jruby implementations where X and Y can be used
  #   to match releases in the 1.8, 1.9, 2.0 or 2.1 series.
  #
  # :mri, :mri_XY ::
  #   Matches non-windows C Ruby (Matz Ruby) or only the 1.8, 1.9, 2.0 or
  #   2.1 series.
  #
  # :mingw, :mingw_XY ::
  #   Matches 32 bit C Ruby on MinGW or only the 1.8, 1.9, 2.0 or 2.1 series.
  #
  # :x64_mingw, :x64_mingw_XY ::
  #   Matches 64 bit C Ruby on MinGW or only the 1.8, 1.9, 2.0 or 2.1 series.
  #
  # :mswin, :mswin_XY ::
  #   Matches 32 bit C Ruby on Microsoft Windows or only the 1.8, 1.9, 2.0 or
  #   2.1 series.
  #
  # :mswin64, :mswin64_XY ::
  #   Matches 64 bit C Ruby on Microsoft Windows or only the 1.8, 1.9, 2.0 or
  #   2.1 series.
  #
  # :jruby, :jruby_XY ::
  #   Matches JRuby or JRuby in 1.8 or 1.9 mode.
  #
  # :maglev ::
  #   Matches Maglev
  #
  # :rbx ::
  #   Matches non-windows Rubinius
  #
  # NOTE:  There is inconsistency in what environment a platform matches.  You
  # may need to read the source to know the exact details.

  def platform(*platforms)
    @current_platforms = platforms

    yield
  ensure
    @current_platforms = nil
  end

  ##
  # :category: Gem Dependencies DSL
  #
  # Block form for restricting gems to a particular set of platforms.  See
  # #platform.

  alias_method :platforms, :platform

  ##
  # :category: Gem Dependencies DSL
  #
  # Restricts this gem dependencies file to the given ruby +version+.
  #
  # You may also provide +engine:+ and +engine_version:+ options to restrict
  # this gem dependencies file to a particular ruby engine and its engine
  # version.  This matching is performed by using the RUBY_ENGINE and
  # RUBY_ENGINE_VERSION constants.

  def ruby(version, options = {})
    engine         = options[:engine]
    engine_version = options[:engine_version]

    raise ArgumentError,
          "You must specify engine_version along with the Ruby engine" if
            engine && !engine_version

    return true if @installing

    unless version == RUBY_VERSION
      message = "Your Ruby version is #{RUBY_VERSION}, " \
                "but your #{gem_deps_file} requires #{version}"

      raise Gem::RubyVersionMismatch, message
    end

    if engine && engine != Gem.ruby_engine
      message = "Your Ruby engine is #{Gem.ruby_engine}, " \
                "but your #{gem_deps_file} requires #{engine}"

      raise Gem::RubyVersionMismatch, message
    end

    if engine_version
      if engine_version != RUBY_ENGINE_VERSION
        message =
          "Your Ruby engine version is #{Gem.ruby_engine} #{RUBY_ENGINE_VERSION}, " \
          "but your #{gem_deps_file} requires #{engine} #{engine_version}"

        raise Gem::RubyVersionMismatch, message
      end
    end

    true
  end

  ##
  # :category: Gem Dependencies DSL
  #
  # Sets +url+ as a source for gems for this dependency API.  RubyGems uses
  # the default configured sources if no source was given.  If a source is set
  # only that source is used.
  #
  # This method differs in behavior from Bundler:
  #
  # * The +:gemcutter+, # +:rubygems+ and +:rubyforge+ sources are not
  #   supported as they are deprecated in bundler.
  # * The +prepend:+ option is not supported.  If you wish to order sources
  #   then list them in your preferred order.

  def source(url)
    Gem.sources.clear if @default_sources

    @default_sources = false

    Gem.sources << url
  end
end
