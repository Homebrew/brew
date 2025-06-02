# frozen_string_literal: true
#
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "deprecate"
require_relative "basic_specification"
require_relative "stub_specification"
require_relative "platform"
require_relative "util/list"

##
# The Specification class contains the information for a gem.  Typically
# defined in a .gemspec file or a Rakefile, and looks like this:
#
#   Gem::Specification.new do |s|
#     s.name        = 'example'
#     s.version     = '0.1.0'
#     s.licenses    = ['MIT']
#     s.summary     = "This is an example!"
#     s.description = "Much longer explanation of the example!"
#     s.authors     = ["Ruby Coder"]
#     s.email       = 'rubycoder@example.com'
#     s.files       = ["lib/example.rb"]
#     s.homepage    = 'https://rubygems.org/gems/example'
#     s.metadata    = { "source_code_uri" => "https://github.com/example/example" }
#   end
#
# Starting in RubyGems 2.0, a Specification can hold arbitrary
# metadata.  See #metadata for restrictions on the format and size of metadata
# items you may add to a specification.

class Gem::Specification < Gem::BasicSpecification
  extend Gem::Deprecate

  # REFACTOR: Consider breaking out this version stuff into a separate
  # module. There's enough special stuff around it that it may justify
  # a separate class.

  ##
  # The version number of a specification that does not specify one
  # (i.e. RubyGems 0.7 or earlier).

  NONEXISTENT_SPECIFICATION_VERSION = -1

  ##
  # The specification version applied to any new Specification instances
  # created.  This should be bumped whenever something in the spec format
  # changes.
  #
  # Specification Version History:
  #
  #   spec   ruby
  #    ver    ver yyyy-mm-dd description
  #     -1 <0.8.0            pre-spec-version-history
  #      1  0.8.0 2004-08-01 Deprecated "test_suite_file" for "test_files"
  #                          "test_file=x" is a shortcut for "test_files=[x]"
  #      2  0.9.5 2007-10-01 Added "required_rubygems_version"
  #                          Now forward-compatible with future versions
  #      3  1.3.2 2009-01-03 Added Fixnum validation to specification_version
  #      4  1.9.0 2011-06-07 Added metadata
  #--
  # When updating this number, be sure to also update #to_ruby.
  #
  # NOTE RubyGems < 1.2 cannot load specification versions > 2.

  CURRENT_SPECIFICATION_VERSION = 4 # :nodoc:

  ##
  # An informal list of changes to the specification.  The highest-valued
  # key should be equal to the CURRENT_SPECIFICATION_VERSION.

  SPECIFICATION_VERSION_HISTORY = { # :nodoc:
    -1 => ["(RubyGems versions up to and including 0.7 did not have versioned specifications)"],
    1  => [
      'Deprecated "test_suite_file" in favor of the new, but equivalent, "test_files"',
      '"test_file=x" is a shortcut for "test_files=[x]"',
    ],
    2 => [
      'Added "required_rubygems_version"',
      "Now forward-compatible with future versions",
    ],
    3 => [
      "Added Fixnum validation to the specification_version",
    ],
    4 => [
      "Added sandboxed freeform metadata to the specification version.",
    ],
  }.freeze

  MARSHAL_FIELDS = { # :nodoc:
    -1 => 16,
     1 => 16,
     2 => 16,
     3 => 17,
     4 => 18,
  }.freeze

  today = Time.now.utc
  TODAY = Time.utc(today.year, today.month, today.day) # :nodoc:

  @load_cache = {} # :nodoc:
  @load_cache_mutex = Thread::Mutex.new

  VALID_NAME_PATTERN = /\A[a-zA-Z0-9\.\-\_]+\z/.freeze # :nodoc:

  # :startdoc:

  ##
  # List of attribute names: [:name, :version, ...]

  @@required_attributes = [:rubygems_version,
                           :specification_version,
                           :name,
                           :version,
                           :date,
                           :summary,
                           :require_paths]

  ##
  # Map of attribute names to default values.

  @@default_value = {
    :authors                   => [],
    :autorequire               => nil,
    :bindir                    => "bin",
    :cert_chain                => [],
    :date                      => nil,
    :dependencies              => [],
    :description               => nil,
    :email                     => nil,
    :executables               => [],
    :extensions                => [],
    :extra_rdoc_files          => [],
    :files                     => [],
    :homepage                  => nil,
    :licenses                  => [],
    :metadata                  => {},
    :name                      => nil,
    :platform                  => Gem::Platform::RUBY,
    :post_install_message      => nil,
    :rdoc_options              => [],
    :require_paths             => ["lib"],
    :required_ruby_version     => Gem::Requirement.default,
    :required_rubygems_version => Gem::Requirement.default,
    :requirements              => [],
    :rubygems_version          => Gem::VERSION,
    :signing_key               => nil,
    :specification_version     => CURRENT_SPECIFICATION_VERSION,
    :summary                   => nil,
    :test_files                => [],
    :version                   => nil,
  }.freeze

  # rubocop:disable Style/MutableConstant
  INITIALIZE_CODE_FOR_DEFAULTS = {} # :nodoc:
  # rubocop:enable Style/MutableConstant

  @@default_value.each do |k,v|
    INITIALIZE_CODE_FOR_DEFAULTS[k] = case v
    when [], {}, true, false, nil, Numeric, Symbol
      v.inspect
    when String
      v.dump
    when Numeric
      "default_value(:#{k})"
    else
      "default_value(:#{k}).dup"
    end
  end

  @@attributes = @@default_value.keys.sort_by {|s| s.to_s }
  @@array_attributes = @@default_value.reject {|k,v| v != [] }.keys
  @@nil_attributes, @@non_nil_attributes = @@default_value.keys.partition do |k|
    @@default_value[k].nil?
  end

  def self.clear_specs # :nodoc:
    @@all = nil
    @@stubs = nil
    @@stubs_by_name = {}
    @@spec_with_requirable_file = {}
    @@active_stub_with_requirable_file = {}
  end
  private_class_method :clear_specs

  clear_specs

  # Sentinel object to represent "not found" stubs
  NOT_FOUND = Struct.new(:to_spec, :this).new # :nodoc:

  # Tracking removed method calls to warn users during build time.
  REMOVED_METHODS = [:rubyforge_project=].freeze # :nodoc:
  def removed_method_calls
    @removed_method_calls ||= []
  end

  ######################################################################
  # :section: Required gemspec attributes

  ##
  # This gem's name.
  #
  # Usage:
  #
  #   spec.name = 'rake'

  attr_accessor :name

  ##
  # This gem's version.
  #
  # The version string can contain numbers and periods, such as +1.0.0+.
  # A gem is a 'prerelease' gem if the version has a letter in it, such as
  # +1.0.0.pre+.
  #
  # Usage:
  #
  #   spec.version = '0.4.1'

  attr_reader :version

  ##
  # A short summary of this gem's description.  Displayed in <tt>gem list -d</tt>.
  #
  # The #description should be more detailed than the summary.
  #
  # Usage:
  #
  #   spec.summary = "This is a small summary of my gem"

  attr_reader :summary

  ##
  # Files included in this gem.  You cannot append to this accessor, you must
  # assign to it.
  #
  # Only add files you can require to this list, not directories, etc.
  #
  # Directories are automatically stripped from this list when building a gem,
  # other non-files cause an error.
  #
  # Usage:
  #
  #   require 'rake'
  #   spec.files = FileList['lib/**/*.rb',
  #                         'bin/*',
  #                         '[A-Z]*'].to_a
  #
  #   # or without Rake...
  #   spec.files = Dir['lib/**/*.rb'] + Dir['bin/*']
  #   spec.files += Dir['[A-Z]*']
  #   spec.files.reject! { |fn| fn.include? "CVS" }

  def files
    # DO NOT CHANGE TO ||= ! This is not a normal accessor. (yes, it sucks)
    # DOC: Why isn't it normal? Why does it suck? How can we fix this?
    @files = [@files,
              @test_files,
              add_bindir(@executables),
              @extra_rdoc_files,
              @extensions,
             ].flatten.compact.uniq.sort
  end

  ##
  # A list of authors for this gem.
  #
  # Alternatively, a single author can be specified by assigning a string to
  # +spec.author+
  #
  # Usage:
  #
  #   spec.authors = ['John Jones', 'Mary Smith']

  def authors=(value)
    @authors = Array(value).flatten.grep(String)
  end

  ######################################################################
  # :section: Recommended gemspec attributes

  ##
  # The version of Ruby required by this gem
  #
  # Usage:
  #
  #   spec.required_ruby_version = '>= 2.7.0'

  attr_reader :required_ruby_version

  ##
  # A long description of this gem
  #
  # The description should be more detailed than the summary but not
  # excessively long.  A few paragraphs is a recommended length with no
  # examples or formatting.
  #
  # Usage:
  #
  #   spec.description = <<-EOF
  #     Rake is a Make-like program implemented in Ruby. Tasks and
  #     dependencies are specified in standard Ruby syntax.
  #   EOF

  attr_reader :description

  ##
  # A contact email address (or addresses) for this gem
  #
  # Usage:
  #
  #   spec.email = 'john.jones@example.com'
  #   spec.email = ['jack@example.com', 'jill@example.com']

  attr_accessor :email

  ##
  # The URL of this gem's home page
  #
  # Usage:
  #
  #   spec.homepage = 'https://github.com/ruby/rake'

  attr_accessor :homepage

  ##
  # The license for this gem.
  #
  # The license must be no more than 64 characters.
  #
  # This should just be the name of your license. The full text of the license
  # should be inside of the gem (at the top level) when you build it.
  #
  # The simplest way is to specify the standard SPDX ID
  # https://spdx.org/licenses/ for the license.
  # Ideally, you should pick one that is OSI (Open Source Initiative)
  # http://opensource.org/licenses/alphabetical approved.
  #
  # The most commonly used OSI-approved licenses are MIT and Apache-2.0.
  # GitHub also provides a license picker at http://choosealicense.com/.
  #
  # You can also use a custom license file along with your gemspec and specify
  # a LicenseRef-<idstring>, where idstring is the name of the file containing
  # the license text.
  #
  # You should specify a license for your gem so that people know how they are
  # permitted to use it and any restrictions you're placing on it.  Not
  # specifying a license means all rights are reserved; others have no right
  # to use the code for any purpose.
  #
  # You can set multiple licenses with #licenses=
  #
  # Usage:
  #   spec.license = 'MIT'

  def license=(o)
    self.licenses = [o]
  end

  ##
  # The license(s) for the library.
  #
  # Each license must be a short name, no more than 64 characters.
  #
  # This should just be the name of your license. The full
  # text of the license should be inside of the gem when you build it.
  #
  # See #license= for more discussion
  #
  # Usage:
  #   spec.licenses = ['MIT', 'GPL-2.0']

  def licenses=(licenses)
    @licenses = Array licenses
  end

  ##
  # The metadata holds extra data for this gem that may be useful to other
  # consumers and is settable by gem authors.
  #
  # Metadata items have the following restrictions:
  #
  # * The metadata must be a Hash object
  # * All keys and values must be Strings
  # * Keys can be a maximum of 128 bytes and values can be a maximum of 1024
  #   bytes
  # * All strings must be UTF-8, no binary data is allowed
  #
  # You can use metadata to specify links to your gem's homepage, codebase,
  # documentation, wiki, mailing list, issue tracker and changelog.
  #
  #   s.metadata = {
  #     "bug_tracker_uri"   => "https://example.com/user/bestgemever/issues",
  #     "changelog_uri"     => "https://example.com/user/bestgemever/CHANGELOG.md",
  #     "documentation_uri" => "https://www.example.info/gems/bestgemever/0.0.1",
  #     "homepage_uri"      => "https://bestgemever.example.io",
  #     "mailing_list_uri"  => "https://groups.example.com/bestgemever",
  #     "source_code_uri"   => "https://example.com/user/bestgemever",
  #     "wiki_uri"          => "https://example.com/user/bestgemever/wiki"
  #     "funding_uri"       => "https://example.com/donate"
  #   }
  #
  # These links will be used on your gem's page on rubygems.org and must pass
  # validation against following regex.
  #
  #   %r{\Ahttps?:\/\/([^\s:@]+:[^\s:@]*@)?[A-Za-z\d\-]+(\.[A-Za-z\d\-]+)+\.?(:\d{1,5})?([\/?]\S*)?\z}

  attr_accessor :metadata

  ######################################################################
  # :section: Optional gemspec attributes

  ##
  # Singular (alternative) writer for #authors
  #
  # Usage:
  #
  #   spec.author = 'John Jones'

  def author=(o)
    self.authors = [o]
  end

  ##
  # The path in the gem for executable scripts.  Usually 'bin'
  #
  # Usage:
  #
  #   spec.bindir = 'bin'

  attr_accessor :bindir

  ##
  # The certificate chain used to sign this gem.  See Gem::Security for
  # details.

  attr_accessor :cert_chain

  ##
  # A message that gets displayed after the gem is installed.
  #
  # Usage:
  #
  #   spec.post_install_message = "Thanks for installing!"

  attr_accessor :post_install_message

  ##
  # The platform this gem runs on.
  #
  # This is usually Gem::Platform::RUBY or Gem::Platform::CURRENT.
  #
  # Most gems contain pure Ruby code; they should simply leave the default
  # value in place.  Some gems contain C (or other) code to be compiled into a
  # Ruby "extension".  The gem should leave the default value in place unless
  # the code will only compile on a certain type of system.  Some gems consist
  # of pre-compiled code ("binary gems").  It's especially important that they
  # set the platform attribute appropriately.  A shortcut is to set the
  # platform to Gem::Platform::CURRENT, which will cause the gem builder to set
  # the platform to the appropriate value for the system on which the build is
  # being performed.
  #
  # If this attribute is set to a non-default value, it will be included in
  # the filename of the gem when it is built such as:
  # nokogiri-1.6.0-x86-mingw32.gem
  #
  # Usage:
  #
  #   spec.platform = Gem::Platform.local

  def platform=(platform)
    if @original_platform.nil? ||
       @original_platform == Gem::Platform::RUBY
      @original_platform = platform
    end

    case platform
    when Gem::Platform::CURRENT then
      @new_platform = Gem::Platform.local
      @original_platform = @new_platform.to_s

    when Gem::Platform then
      @new_platform = platform

    # legacy constants
    when nil, Gem::Platform::RUBY then
      @new_platform = Gem::Platform::RUBY
    when "mswin32" then # was Gem::Platform::WIN32
      @new_platform = Gem::Platform.new "x86-mswin32"
    when "i586-linux" then # was Gem::Platform::LINUX_586
      @new_platform = Gem::Platform.new "x86-linux"
    when "powerpc-darwin" then # was Gem::Platform::DARWIN
      @new_platform = Gem::Platform.new "ppc-darwin"
    else
      @new_platform = Gem::Platform.new platform
    end

    @platform = @new_platform.to_s

    invalidate_memoized_attributes

    @new_platform
  end

  ##
  # Paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.
  #--
  # See also #require_paths
  #++
  # If you have an extension you do not need to add <code>"ext"</code> to the
  # require path, the extension build process will copy the extension files
  # into "lib" for you.
  #
  # The default value is <code>"lib"</code>
  #
  # Usage:
  #
  #   # If all library files are in the root directory...
  #   spec.require_paths = ['.']

  def require_paths=(val)
    @require_paths = Array(val)
  end

  ##
  # The RubyGems version required by this gem

  attr_reader :required_rubygems_version

  ##
  # The version of RubyGems used to create this gem.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  attr_accessor :rubygems_version

  ##
  # The key used to sign this gem.  See Gem::Security for details.

  attr_accessor :signing_key

  ##
  # Adds a development dependency named +gem+ with +requirements+ to this
  # gem.
  #
  # Usage:
  #
  #   spec.add_development_dependency 'example', '~> 1.1', '>= 1.1.4'
  #
  # Development dependencies aren't installed by default and aren't
  # activated when a gem is required.

  def add_development_dependency(gem, *requirements)
    add_dependency_with_type(gem, :development, requirements)
  end

  ##
  # Adds a runtime dependency named +gem+ with +requirements+ to this gem.
  #
  # Usage:
  #
  #   spec.add_runtime_dependency 'example', '~> 1.1', '>= 1.1.4'

  def add_runtime_dependency(gem, *requirements)
    if requirements.uniq.size != requirements.size
      warn "WARNING: duplicated #{gem} dependency #{requirements}"
    end

    add_dependency_with_type(gem, :runtime, requirements)
  end

  ##
  # Executables included in the gem.
  #
  # For example, the rake gem has rake as an executable. You don’t specify the
  # full path (as in bin/rake); all application-style files are expected to be
  # found in bindir.  These files must be executable Ruby files.  Files that
  # use bash or other interpreters will not work.
  #
  # Executables included may only be ruby scripts, not scripts for other
  # languages or compiled binaries.
  #
  # Usage:
  #
  #   spec.executables << 'rake'

  def executables
    @executables ||= []
  end

  ##
  # Extensions to build when installing the gem, specifically the paths to
  # extconf.rb-style files used to compile extensions.
  #
  # These files will be run when the gem is installed, causing the C (or
  # whatever) code to be compiled on the user’s machine.
  #
  # Usage:
  #
  #  spec.extensions << 'ext/rmagic/extconf.rb'
  #
  # See Gem::Ext::Builder for information about writing extensions for gems.

  def extensions
    @extensions ||= []
  end

  ##
  # Extra files to add to RDoc such as README or doc/examples.txt
  #
  # When the user elects to generate the RDoc documentation for a gem (typically
  # at install time), all the library files are sent to RDoc for processing.
  # This option allows you to have some non-code files included for a more
  # complete set of documentation.
  #
  # Usage:
  #
  #  spec.extra_rdoc_files = ['README', 'doc/user-guide.txt']

  def extra_rdoc_files
    @extra_rdoc_files ||= []
  end

  ##
  # The version of RubyGems that installed this gem.  Returns
  # <code>Gem::Version.new(0)</code> for gems installed by versions earlier
  # than RubyGems 2.2.0.

  def installed_by_version # :nodoc:
    @installed_by_version ||= Gem::Version.new(0)
  end

  ##
  # Sets the version of RubyGems that installed this gem.  See also
  # #installed_by_version.

  def installed_by_version=(version) # :nodoc:
    @installed_by_version = Gem::Version.new version
  end

  ##
  # Specifies the rdoc options to be used when generating API documentation.
  #
  # Usage:
  #
  #   spec.rdoc_options << '--title' << 'Rake -- Ruby Make' <<
  #     '--main' << 'README' <<
  #     '--line-numbers'

  def rdoc_options
    @rdoc_options ||= []
  end

  LATEST_RUBY_WITHOUT_PATCH_VERSIONS = Gem::Version.new("2.1")

  ##
  # The version of Ruby required by this gem.  The ruby version can be
  # specified to the patch-level:
  #
  #   $ ruby -v -e 'p Gem.ruby_version'
  #   ruby 2.0.0p247 (2013-06-27 revision 41674) [x86_64-darwin12.4.0]
  #   #<Gem::Version "2.0.0.247">
  #
  # Prereleases can also be specified.
  #
  # Usage:
  #
  #  # This gem will work with 1.8.6 or greater...
  #  spec.required_ruby_version = '>= 1.8.6'
  #
  #  # Only with final releases of major version 2 where minor version is at least 3
  #  spec.required_ruby_version = '~> 2.3'
  #
  #  # Only prereleases or final releases after 2.6.0.preview2
  #  spec.required_ruby_version = '> 2.6.0.preview2'
  #
  #  # This gem will work with 2.3.0 or greater, including major version 3, but lesser than 4.0.0
  #  spec.required_ruby_version = '>= 2.3', '< 4'

  def required_ruby_version=(req)
    @required_ruby_version = Gem::Requirement.create req

    @required_ruby_version.requirements.map! do |op, v|
      if v >= LATEST_RUBY_WITHOUT_PATCH_VERSIONS && v.release.segments.size == 4
        [op == "~>" ? "=" : op, Gem::Version.new(v.segments.tap {|s| s.delete_at(3) }.join("."))]
      else
        [op, v]
      end
    end
  end

  ##
  # The RubyGems version required by this gem

  def required_rubygems_version=(req)
    @required_rubygems_version = Gem::Requirement.create req
  end

  ##
  # Lists the external (to RubyGems) requirements that must be met for this gem
  # to work.  It's simply information for the user.
  #
  # Usage:
  #
  #   spec.requirements << 'libmagick, v6.0'
  #   spec.requirements << 'A good graphics card'

  def requirements
    @requirements ||= []
  end

  ##
  # A collection of unit test files.  They will be loaded as unit tests when
  # the user requests a gem to be unit tested.
  #
  # Usage:
  #   spec.test_files = Dir.glob('test/tc_*.rb')
  #   spec.test_files = ['tests/test-suite.rb']

  def test_files=(files) # :nodoc:
    @test_files = Array files
  end

  ######################################################################
  # :section: Specification internals

  ##
  # True when this gemspec has been activated. This attribute is not persisted.

  attr_accessor :activated

  alias :activated? :activated

  ##
  # Autorequire was used by old RubyGems to automatically require a file.
  #
  # Deprecated: It is neither supported nor functional.

  attr_accessor :autorequire # :nodoc:

  ##
  # Sets the default executable for this gem.
  #
  # Deprecated: You must now specify the executable name to  Gem.bin_path.

  attr_writer :default_executable
  rubygems_deprecate :default_executable=

  ##
  # Allows deinstallation of gems with legacy platforms.

  attr_writer :original_platform # :nodoc:

  ##
  # The Gem::Specification version of this gemspec.
  #
  # Do not set this, it is set automatically when the gem is packaged.

  attr_accessor :specification_version

  def self._all # :nodoc:
    @@all ||= Gem.loaded_specs.values | stubs.map(&:to_spec)
  end

  def self.clear_load_cache # :nodoc:
    @load_cache_mutex.synchronize do
      @load_cache.clear
    end
  end
  private_class_method :clear_load_cache

  def self.each_gemspec(dirs) # :nodoc:
    dirs.each do |dir|
      Gem::Util.glob_files_in_dir("*.gemspec", dir).each do |path|
        yield path.tap(&Gem::UNTAINT)
      end
    end
  end

  def self.gemspec_stubs_in(dir, pattern)
    Gem::Util.glob_files_in_dir(pattern, dir).map {|path| yield path }.select(&:valid?)
  end
  private_class_method :gemspec_stubs_in

  def self.installed_stubs(dirs, pattern)
    map_stubs(dirs, pattern) do |path, base_dir, gems_dir|
      Gem::StubSpecification.gemspec_stub(path, base_dir, gems_dir)
    end
  end
  private_class_method :installed_stubs

  def self.map_stubs(dirs, pattern) # :nodoc:
    dirs.flat_map do |dir|
      base_dir = File.dirname dir
      gems_dir = File.join base_dir, "gems"
      gemspec_stubs_in(dir, pattern) {|path| yield path, base_dir, gems_dir }
    end
  end
  private_class_method :map_stubs

  def self.each_spec(dirs) # :nodoc:
    each_gemspec(dirs) do |path|
      spec = self.load path
      yield spec if spec
    end
  end

  ##
  # Returns a Gem::StubSpecification for every installed gem

  def self.stubs
    @@stubs ||= begin
      pattern = "*.gemspec"
      stubs = stubs_for_pattern(pattern, false)

      @@stubs_by_name = stubs.select {|s| Gem::Platform.match_spec? s }.group_by(&:name)
      stubs
    end
  end

  ##
  # Returns a Gem::StubSpecification for default gems

  def self.default_stubs(pattern = "*.gemspec")
    base_dir = Gem.default_dir
    gems_dir = File.join base_dir, "gems"
    gemspec_stubs_in(Gem.default_specifications_dir, pattern) do |path|
      Gem::StubSpecification.default_gemspec_stub(path, base_dir, gems_dir)
    end
  end

  ##
  # Returns a Gem::StubSpecification for installed gem named +name+
  # only returns stubs that match Gem.platforms

  def self.stubs_for(name)
    if @@stubs
      @@stubs_by_name[name] || []
    else
      @@stubs_by_name[name] ||= stubs_for_pattern("#{name}-*.gemspec").select do |s|
        s.name == name
      end
    end
  end

  ##
  # Finds stub specifications matching a pattern from the standard locations,
  # optionally filtering out specs not matching the current platform
  #
  def self.stubs_for_pattern(pattern, match_platform = true) # :nodoc:
    installed_stubs = installed_stubs(Gem::Specification.dirs, pattern)
    installed_stubs.select! {|s| Gem::Platform.match_spec? s } if match_platform
    stubs = installed_stubs + default_stubs(pattern)
    stubs = stubs.uniq {|stub| stub.full_name }
    _resort!(stubs)
    stubs
  end

  def self._resort!(specs) # :nodoc:
    specs.sort! do |a, b|
      names = a.name <=> b.name
      next names if names.nonzero?
      versions = b.version <=> a.version
      next versions if versions.nonzero?
      Gem::Platform.sort_priority(b.platform)
    end
  end

  ##
  # Loads the default specifications. It should be called only once.

  def self.load_defaults
    each_spec([Gem.default_specifications_dir]) do |spec|
      # #load returns nil if the spec is bad, so we just ignore
      # it at this stage
      Gem.register_default_spec(spec)
    end
  end

  ##
  # Adds +spec+ to the known specifications, keeping the collection
  # properly sorted.

  def self.add_spec(spec)
    return if _all.include? spec

    _all << spec
    stubs << spec
    (@@stubs_by_name[spec.name] ||= []) << spec

    _resort!(@@stubs_by_name[spec.name])
    _resort!(stubs)
  end

  ##
  # Removes +spec+ from the known specs.

  def self.remove_spec(spec)
    _all.delete spec.to_spec
    stubs.delete spec
    (@@stubs_by_name[spec.name] || []).delete spec
  end

  ##
  # Returns all specifications. This method is discouraged from use.
  # You probably want to use one of the Enumerable methods instead.

  def self.all
    warn "NOTE: Specification.all called from #{caller.first}" unless
      Gem::Deprecate.skip
    _all
  end

  ##
  # Sets the known specs to +specs+. Not guaranteed to work for you in
  # the future. Use at your own risk. Caveat emptor. Doomy doom doom.
  # Etc etc.
  #
  #--
  # Makes +specs+ the known specs
  # Listen, time is a river
  # Winter comes, code breaks
  #
  # -- wilsonb

  def self.all=(specs)
    @@stubs_by_name = specs.group_by(&:name)
    @@all = @@stubs = specs
  end

  ##
  # Return full names of all specs in sorted order.

  def self.all_names
    self._all.map(&:full_name)
  end

  ##
  # Return the list of all array-oriented instance variables.
  #--
  # Not sure why we need to use so much stupid reflection in here...

  def self.array_attributes
    @@array_attributes.dup
  end

  ##
  # Return the list of all instance variables.
  #--
  # Not sure why we need to use so much stupid reflection in here...

  def self.attribute_names
    @@attributes.dup
  end

  ##
  # Return the directories that Specification uses to find specs.

  def self.dirs
    @@dirs ||= Gem.path.collect do |dir|
      File.join dir.dup.tap(&Gem::UNTAINT), "specifications"
    end
  end

  ##
  # Set the directories that Specification uses to find specs. Setting
  # this resets the list of known specs.

  def self.dirs=(dirs)
    self.reset

    @@dirs = Array(dirs).map {|dir| File.join dir, "specifications" }
  end

  extend Enumerable

  ##
  # Enumerate every known spec.  See ::dirs= and ::add_spec to set the list of
  # specs.

  def self.each
    return enum_for(:each) unless block_given?

    self._all.each do |x|
      yield x
    end
  end

  ##
  # Returns every spec that matches +name+ and optional +requirements+.

  def self.find_all_by_name(name, *requirements)
    requirements = Gem::Requirement.default if requirements.empty?

    # TODO: maybe try: find_all { |s| spec === dep }

    Gem::Dependency.new(name, *requirements).matching_specs
  end

  ##
  # Returns every spec that has the given +full_name+

  def self.find_all_by_full_name(full_name)
    stubs.select {|s| s.full_name == full_name }.map(&:to_spec)
  end

  ##
  # Find the best specification matching a +name+ and +requirements+. Raises
  # if the dependency doesn't resolve to a valid specification.

  def self.find_by_name(name, *requirements)
    requirements = Gem::Requirement.default if requirements.empty?

    # TODO: maybe try: find { |s| spec === dep }

    Gem::Dependency.new(name, *requirements).to_spec
  end

  ##
  # Return the best specification that contains the file matching +path+.

  def self.find_by_path(path)
    path = path.dup.freeze
    spec = @@spec_with_requirable_file[path] ||= (stubs.find do |s|
      s.contains_requirable_file? path
    end || NOT_FOUND)
    spec.to_spec
  end

  ##
  # Return the best specification that contains the file matching +path+
  # amongst the specs that are not activated.

  def self.find_inactive_by_path(path)
    stub = stubs.find do |s|
      next if s.activated?
      s.contains_requirable_file? path
    end
    stub && stub.to_spec
  end

  def self.find_active_stub_by_path(path)
    stub = @@active_stub_with_requirable_file[path] ||= (stubs.find do |s|
      s.activated? && s.contains_requirable_file?(path)
    end || NOT_FOUND)
    stub.this
  end

  ##
  # Return currently unresolved specs that contain the file matching +path+.

  def self.find_in_unresolved(path)
    unresolved_specs.find_all {|spec| spec.contains_requirable_file? path }
  end

  ##
  # Search through all unresolved deps and sub-dependencies and return
  # specs that contain the file matching +path+.

  def self.find_in_unresolved_tree(path)
    unresolved_specs.each do |spec|
      spec.traverse do |from_spec, dep, to_spec, trail|
        if to_spec.has_conflicts? || to_spec.conficts_when_loaded_with?(trail)
          :next
        else
          return trail.reverse if to_spec.contains_requirable_file? path
        end
      end
    end

    []
  end

  def self.unresolved_specs
    unresolved_deps.values.map {|dep| dep.to_specs }.flatten
  end
  private_class_method :unresolved_specs

  ##
  # Special loader for YAML files.  When a Specification object is loaded
  # from a YAML file, it bypasses the normal Ruby object initialization
  # routine (#initialize).  This method makes up for that and deals with
  # gems of different ages.
  #
  # +input+ can be anything that YAML.load() accepts: String or IO.

  def self.from_yaml(input)
    Gem.load_yaml

    input = normalize_yaml_input input
    spec = Gem::SafeYAML.safe_load input

    if spec && spec.class == FalseClass
      raise Gem::EndOfYAMLException
    end

    unless Gem::Specification === spec
      raise Gem::Exception, "YAML data doesn't evaluate to gem specification"
    end

    spec.specification_version ||= NONEXISTENT_SPECIFICATION_VERSION
    spec.reset_nil_attributes_to_default
    spec.flatten_require_paths

    spec
  end

  ##
  # Return the latest specs, optionally including prerelease specs if
  # +prerelease+ is true.

  def self.latest_specs(prerelease = false)
    _latest_specs Gem::Specification.stubs, prerelease
  end

  ##
  # Return the latest installed spec for gem +name+.

  def self.latest_spec_for(name)
    latest_specs(true).find {|installed_spec| installed_spec.name == name }
  end

  def self._latest_specs(specs, prerelease = false) # :nodoc:
    result = {}

    specs.reverse_each do |spec|
      next if spec.version.prerelease? unless prerelease

      result[spec.name] = spec
    end

    result.map(&:last).flatten.sort_by {|tup| tup.name }
  end

  ##
  # Loads Ruby format gemspec from +file+.

  def self.load(file)
    return unless file

    _spec = @load_cache_mutex.synchronize { @load_cache[file] }
    return _spec if _spec

    file = file.dup.tap(&Gem::UNTAINT)
    return unless File.file?(file)

    code = Gem.open_file(file, "r:UTF-8:-", &:read)

    code.tap(&Gem::UNTAINT)

    begin
      _spec = eval code, binding, file

      if Gem::Specification === _spec
        _spec.loaded_from = File.expand_path file.to_s
        @load_cache_mutex.synchronize do
          prev = @load_cache[file]
          if prev
            _spec = prev
          else
            @load_cache[file] = _spec
          end
        end
        return _spec
      end

      warn "[#{file}] isn't a Gem::Specification (#{_spec.class} instead)."
    rescue SignalException, SystemExit
      raise
    rescue SyntaxError, Exception => e
      warn "Invalid gemspec in [#{file}]: #{e}"
    end

    nil
  end

  ##
  # Specification attributes that must be non-nil

  def self.non_nil_attributes
    @@non_nil_attributes.dup
  end

  ##
  # Make sure the YAML specification is properly formatted with dashes

  def self.normalize_yaml_input(input)
    result = input.respond_to?(:read) ? input.read : input
    result = "--- " + result unless result.start_with?("--- ")
    result = result.dup
    result.gsub!(/ !!null \n/, " \n")
    # date: 2011-04-26 00:00:00.000000000Z
    # date: 2011-04-26 00:00:00.000000000 Z
    result.gsub!(/^(date: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+?)Z/, '\1 Z')
    result
  end

  ##
  # Return a list of all outdated local gem names.  This method is HEAVY
  # as it must go fetch specifications from the server.
  #
  # Use outdated_and_latest_version if you wish to retrieve the latest remote
  # version as well.

  def self.outdated
    outdated_and_latest_version.map {|local, _| local.name }
  end

  ##
  # Enumerates the outdated local gems yielding the local specification and
  # the latest remote version.
  #
  # This method may take some time to return as it must check each local gem
  # against the server's index.

  def self.outdated_and_latest_version
    return enum_for __method__ unless block_given?

    # TODO: maybe we should switch to rubygems' version service?
    fetcher = Gem::SpecFetcher.fetcher

    latest_specs(true).each do |local_spec|
      dependency =
        Gem::Dependency.new local_spec.name, ">= #{local_spec.version}"

      remotes, = fetcher.search_for_dependency dependency
      remotes  = remotes.map {|n, _| n.version }

      latest_remote = remotes.sort.last

      yield [local_spec, latest_remote] if
        latest_remote && local_spec.version < latest_remote
    end

    nil
  end

  ##
  # Is +name+ a required attribute?

  def self.required_attribute?(name)
    @@required_attributes.include? name.to_sym
  end

  ##
  # Required specification attributes

  def self.required_attributes
    @@required_attributes.dup
  end

  ##
  # Reset the list of known specs, running pre and post reset hooks
  # registered in Gem.

  def self.reset
    @@dirs = nil
    Gem.pre_reset_hooks.each {|hook| hook.call }
    clear_specs
    clear_load_cache
    unresolved = unresolved_deps
    unless unresolved.empty?
      w = "W" + "ARN"
      warn "#{w}: Unresolved or ambiguous specs during Gem::Specification.reset:"
      unresolved.values.each do |dep|
        warn "      #{dep}"

        versions = find_all_by_name(dep.name)
        unless versions.empty?
          warn "      Available/installed versions of this gem:"
          versions.each {|s| warn "      - #{s.version}" }
        end
      end
      warn "#{w}: Clearing out unresolved specs. Try 'gem cleanup <gem>'"
      warn "Please report a bug if this causes problems."
      unresolved.clear
    end
    Gem.post_reset_hooks.each {|hook| hook.call }
  end

  # DOC: This method needs documented or nodoc'd
  def self.unresolved_deps
    @unresolved_deps ||= Hash.new {|h, n| h[n] = Gem::Dependency.new n }
  end

  ##
  # Load custom marshal format, re-initializing defaults as needed

  def self._load(str)
    Gem.load_yaml

    array = begin
      Marshal.load str
    rescue ArgumentError => e
      #
      # Some very old marshaled specs included references to `YAML::PrivateType`
      # and `YAML::Syck::DefaultKey` constants due to bugs in the old emitter
      # that generated them. Workaround the issue by defining the necessary
      # constants and retrying.
      #
      message = e.message
      raise unless message.include?("YAML::")

      Object.const_set "YAML", Psych unless Object.const_defined?(:YAML)

      if message.include?("YAML::Syck::")
        YAML.const_set "Syck", YAML unless YAML.const_defined?(:Syck)

        YAML::Syck.const_set "DefaultKey", Class.new if message.include?("YAML::Syck::DefaultKey")
      elsif message.include?("YAML::PrivateType")
        YAML.const_set "PrivateType", Class.new
      end

      retry
    end

    spec = Gem::Specification.new
    spec.instance_variable_set :@specification_version, array[1]

    current_version = CURRENT_SPECIFICATION_VERSION

    field_count = if spec.specification_version > current_version
      spec.instance_variable_set :@specification_version,
                                 current_version
      MARSHAL_FIELDS[current_version]
    else
      MARSHAL_FIELDS[spec.specification_version]
    end

    if array.size < field_count
      raise TypeError, "invalid Gem::Specification format #{array.inspect}"
    end

    spec.instance_variable_set :@rubygems_version,          array[0]
    # spec version
    spec.instance_variable_set :@name,                      array[2]
    spec.instance_variable_set :@version,                   array[3]
    spec.date =                                             array[4]
    spec.instance_variable_set :@summary,                   array[5]
    spec.instance_variable_set :@required_ruby_version,     array[6]
    spec.instance_variable_set :@required_rubygems_version, array[7]
    spec.instance_variable_set :@original_platform,         array[8]
    spec.instance_variable_set :@dependencies,              array[9]
    # offset due to rubyforge_project removal
    spec.instance_variable_set :@email,                     array[11]
    spec.instance_variable_set :@authors,                   array[12]
    spec.instance_variable_set :@description,               array[13]
    spec.instance_variable_set :@homepage,                  array[14]
    spec.instance_variable_set :@has_rdoc,                  array[15]
    spec.instance_variable_set :@new_platform,              array[16]
    spec.instance_variable_set :@platform,                  array[16].to_s
    spec.instance_variable_set :@license,                   array[17]
    spec.instance_variable_set :@metadata,                  array[18]
    spec.instance_variable_set :@loaded,                    false
    spec.instance_variable_set :@activated,                 false

    spec
  end

  def <=>(other) # :nodoc:
    sort_obj <=> other.sort_obj
  end

  def ==(other) # :nodoc:
    self.class === other &&
      name == other.name &&
      version == other.version &&
      platform == other.platform
  end

  ##
  # Dump only crucial instance variables.
  #--
  # MAINTAIN ORDER!
  # (down with the man)

  def _dump(limit)
    Marshal.dump [
      @rubygems_version,
      @specification_version,
      @name,
      @version,
      date,
      @summary,
      @required_ruby_version,
      @required_rubygems_version,
      @original_platform,
      @dependencies,
      "", # rubyforge_project
      @email,
      @authors,
      @description,
      @homepage,
      true, # has_rdoc
      @new_platform,
      @licenses,
      @metadata,
    ]
  end

  ##
  # Activate this spec, registering it as a loaded spec and adding
  # it's lib paths to $LOAD_PATH. Returns true if the spec was
  # activated, false if it was previously activated. Freaks out if
  # there are conflicts upon activation.

  def activate
    other = Gem.loaded_specs[self.name]
    if other
      check_version_conflict other
      return false
    end

    raise_if_conflicts

    activate_dependencies
    add_self_to_load_path

    Gem.loaded_specs[self.name] = self
    @activated = true
    @loaded = true

    return true
  end

  ##
  # Activate all unambiguously resolved runtime dependencies of this
  # spec. Add any ambiguous dependencies to the unresolved list to be
  # resolved later, as needed.

  def activate_dependencies
    unresolved = Gem::Specification.unresolved_deps

    self.runtime_dependencies.each do |spec_dep|
      if loaded = Gem.loaded_specs[spec_dep.name]
        next if spec_dep.matches_spec? loaded

        msg = "can't satisfy '#{spec_dep}', already activated '#{loaded.full_name}'"
        e = Gem::LoadError.new msg
        e.name = spec_dep.name

        raise e
      end

      begin
        specs = spec_dep.to_specs
      rescue Gem::MissingSpecError => e
        raise Gem::MissingSpecError.new(e.name, e.requirement, "at: #{self.spec_file}")
      end

      if specs.size == 1
        specs.first.activate
      else
        name = spec_dep.name
        unresolved[name] = unresolved[name].merge spec_dep
      end
    end

    unresolved.delete self.name
  end

  ##
  # Abbreviate the spec for downloading.  Abbreviated specs are only used for
  # searching, downloading and related activities and do not need deployment
  # specific information (e.g. list of files).  So we abbreviate the spec,
  # making it much smaller for quicker downloads.

  def abbreviate
    self.files = []
    self.test_files = []
    self.rdoc_options = []
    self.extra_rdoc_files = []
    self.cert_chain = []
  end

  ##
  # Sanitize the descriptive fields in the spec.  Sometimes non-ASCII
  # characters will garble the site index.  Non-ASCII characters will
  # be replaced by their XML entity equivalent.

  def sanitize
    self.summary              = sanitize_string(summary)
    self.description          = sanitize_string(description)
    self.post_install_message = sanitize_string(post_install_message)
    self.authors              = authors.collect {|a| sanitize_string(a) }
  end

  ##
  # Sanitize a single string.

  def sanitize_string(string)
    return string unless string

    # HACK the #to_s is in here because RSpec has an Array of Arrays of
    # Strings for authors.  Need a way to disallow bad values on gemspec
    # generation.  (Probably won't happen.)
    string.to_s
  end

  ##
  # Returns an array with bindir attached to each executable in the
  # +executables+ list

  def add_bindir(executables)
    return nil if executables.nil?

    if @bindir
      Array(executables).map {|e| File.join(@bindir, e) }
    else
      executables
    end
  rescue
    return nil
  end

  ##
  # Adds a dependency on gem +dependency+ with type +type+ that requires
  # +requirements+.  Valid types are currently <tt>:runtime</tt> and
  # <tt>:development</tt>.

  def add_dependency_with_type(dependency, type, requirements)
    requirements = if requirements.empty?
      Gem::Requirement.default
    else
      requirements.flatten
    end

    unless dependency.respond_to?(:name) &&
           dependency.respond_to?(:requirement)
      dependency = Gem::Dependency.new(dependency.to_s, requirements, type)
    end

    dependencies << dependency
  end

  private :add_dependency_with_type

  alias add_dependency add_runtime_dependency

  ##
  # Adds this spec's require paths to LOAD_PATH, in the proper location.

  def add_self_to_load_path
    return if default_gem?

    paths = full_require_paths

    Gem.add_to_load_path(*paths)
  end

  ##
  # Singular reader for #authors.  Returns the first author in the list

  def author
    (val = authors) && val.first
  end

  ##
  # The list of author names who wrote this gem.
  #
  #   spec.authors = ['Chad Fowler', 'Jim Weirich', 'Rich Kilmer']

  def authors
    @authors ||= []
  end

  ##
  # Returns the full path to installed gem's bin directory.
  #
  # NOTE: do not confuse this with +bindir+, which is just 'bin', not
  # a full path.

  def bin_dir
    @bin_dir ||= File.join gem_dir, bindir
  end

  ##
  # Returns the full path to an executable named +name+ in this gem.

  def bin_file(name)
    File.join bin_dir, name
  end

  ##
  # Returns the build_args used to install the gem

  def build_args
    if File.exist? build_info_file
      build_info = File.readlines build_info_file
      build_info = build_info.map {|x| x.strip }
      build_info.delete ""
      build_info
    else
      []
    end
  end

  ##
  # Builds extensions for this platform if the gem has extensions listed and
  # the gem.build_complete file is missing.

  def build_extensions # :nodoc:
    return if extensions.empty?
    return if default_gem?
    return if File.exist? gem_build_complete_path
    return if !File.writable?(base_dir)
    return if !File.exist?(File.join(base_dir, "extensions"))

    begin
      # We need to require things in $LOAD_PATH without looking for the
      # extension we are about to build.
      unresolved_deps = Gem::Specification.unresolved_deps.dup
      Gem::Specification.unresolved_deps.clear

      require_relative "config_file"
      require_relative "ext"
      require_relative "user_interaction"

      ui = Gem::SilentUI.new
      Gem::DefaultUserInteraction.use_ui ui do
        builder = Gem::Ext::Builder.new self
        builder.build_extensions
      end
    ensure
      ui.close if ui
      Gem::Specification.unresolved_deps.replace unresolved_deps
    end
  end

  ##
  # Returns the full path to the build info directory

  def build_info_dir
    File.join base_dir, "build_info"
  end

  ##
  # Returns the full path to the file containing the build
  # information generated when the gem was installed

  def build_info_file
    File.join build_info_dir, "#{full_name}.info"
  end

  ##
  # Returns the full path to the cache directory containing this
  # spec's cached gem.

  def cache_dir
    @cache_dir ||= File.join base_dir, "cache"
  end

  ##
  # Returns the full path to the cached gem for this spec.

  def cache_file
    @cache_file ||= File.join cache_dir, "#{full_name}.gem"
  end

  ##
  # Return any possible conflicts against the currently loaded specs.

  def conflicts
    conflicts = {}
    self.runtime_dependencies.each do |dep|
      spec = Gem.loaded_specs[dep.name]
      if spec && !spec.satisfies_requirement?(dep)
        (conflicts[spec] ||= []) << dep
      end
    end
    env_req = Gem.env_requirement(name)
    (conflicts[self] ||= []) << env_req unless env_req.satisfied_by? version
    conflicts
  end

  ##
  # return true if there will be conflict when spec if loaded together with the list of specs.

  def conficts_when_loaded_with?(list_of_specs) # :nodoc:
    result = list_of_specs.any? do |spec|
      spec.dependencies.any? {|dep| dep.runtime? && (dep.name == name) && !satisfies_requirement?(dep) }
    end
    result
  end

  ##
  # Return true if there are possible conflicts against the currently loaded specs.

  def has_conflicts?
    return true unless Gem.env_requirement(name).satisfied_by?(version)
    self.dependencies.any? do |dep|
      if dep.runtime?
        spec = Gem.loaded_specs[dep.name]
        spec && !spec.satisfies_requirement?(dep)
      else
        false
      end
    end
  end

  # The date this gem was created.
  #
  # If SOURCE_DATE_EPOCH is set as an environment variable, use that to support
  # reproducible builds; otherwise, default to the current UTC date.
  #
  # Details on SOURCE_DATE_EPOCH:
  # https://reproducible-builds.org/specs/source-date-epoch/

  def date
    @date ||= Time.utc(*Gem.source_date_epoch.utc.to_a[3..5].reverse)
  end

  DateLike = Object.new # :nodoc:
  def DateLike.===(obj) # :nodoc:
    defined?(::Date) && Date === obj
  end

  DateTimeFormat = # :nodoc:
    /\A
     (\d{4})-(\d{2})-(\d{2})
     (\s+ \d{2}:\d{2}:\d{2}\.\d+ \s* (Z | [-+]\d\d:\d\d) )?
     \Z/x.freeze

  ##
  # The date this gem was created
  #
  # DO NOT set this, it is set automatically when the gem is packaged.

  def date=(date)
    # We want to end up with a Time object with one-day resolution.
    # This is the cleanest, most-readable, faster-than-using-Date
    # way to do it.
    @date = case date
    when String then
      if DateTimeFormat =~ date
        Time.utc($1.to_i, $2.to_i, $3.to_i)
      else
        raise(Gem::InvalidSpecificationException,
              "invalid date format in specification: #{date.inspect}")
      end
    when Time, DateLike then
      Time.utc(date.year, date.month, date.day)
    else
      TODAY
    end
  end

  ##
  # The default executable for this gem.
  #
  # Deprecated: The name of the gem is assumed to be the name of the
  # executable now.  See Gem.bin_path.

  def default_executable # :nodoc:
    if defined?(@default_executable) && @default_executable
      result = @default_executable
    elsif @executables && @executables.size == 1
      result = Array(@executables).first
    else
      result = nil
    end
    result
  end
  rubygems_deprecate :default_executable

  ##
  # The default value for specification attribute +name+

  def default_value(name)
    @@default_value[name]
  end

  ##
  # A list of Gem::Dependency objects this gem depends on.
  #
  # Use #add_dependency or #add_development_dependency to add dependencies to
  # a gem.

  def dependencies
    @dependencies ||= []
  end

  ##
  # Return a list of all gems that have a dependency on this gemspec.  The
  # list is structured with entries that conform to:
  #
  #   [depending_gem, dependency, [list_of_gems_that_satisfy_dependency]]

  def dependent_gems(check_dev=true)
    out = []
    Gem::Specification.each do |spec|
      deps = check_dev ? spec.dependencies : spec.runtime_dependencies
      deps.each do |dep|
        if self.satisfies_requirement?(dep)
          sats = []
          find_all_satisfiers(dep) do |sat|
            sats << sat
          end
          out << [spec, dep, sats]
        end
      end
    end
    out
  end

  ##
  # Returns all specs that matches this spec's runtime dependencies.

  def dependent_specs
    runtime_dependencies.map {|dep| dep.to_specs }.flatten
  end

  ##
  # A detailed description of this gem.  See also #summary

  def description=(str)
    @description = str.to_s
  end

  ##
  # List of dependencies that are used for development

  def development_dependencies
    dependencies.select {|d| d.type == :development }
  end

  ##
  # Returns the full path to this spec's documentation directory.  If +type+
  # is given it will be appended to the end.  For example:
  #
  #   spec.doc_dir      # => "/path/to/gem_repo/doc/a-1"
  #
  #   spec.doc_dir 'ri' # => "/path/to/gem_repo/doc/a-1/ri"

  def doc_dir(type = nil)
    @doc_dir ||= File.join base_dir, "doc", full_name

    if type
      File.join @doc_dir, type
    else
      @doc_dir
    end
  end

  def encode_with(coder) # :nodoc:
    mark_version

    coder.add "name", @name
    coder.add "version", @version
    platform = case @original_platform
    when nil, "" then
      "ruby"
    when String then
      @original_platform
    else
      @original_platform.to_s
    end
    coder.add "platform", platform

    attributes = @@attributes.map(&:to_s) - %w[name version platform]
    attributes.each do |name|
      coder.add name, instance_variable_get("@#{name}")
    end
  end

  def eql?(other) # :nodoc:
    self.class === other && same_attributes?(other)
  end

  ##
  # Singular accessor for #executables

  def executable
    (val = executables) && val.first
  end

  ##
  # Singular accessor for #executables

  def executable=(o)
    self.executables = [o]
  end

  ##
  # Sets executables to +value+, ensuring it is an array.

  def executables=(value)
    @executables = Array(value)
  end

  ##
  # Sets extensions to +extensions+, ensuring it is an array.

  def extensions=(extensions)
    @extensions = Array extensions
  end

  ##
  # Sets extra_rdoc_files to +files+, ensuring it is an array.

  def extra_rdoc_files=(files)
    @extra_rdoc_files = Array files
  end

  ##
  # The default (generated) file name of the gem.  See also #spec_name.
  #
  #   spec.file_name # => "example-1.0.gem"

  def file_name
    "#{full_name}.gem"
  end

  ##
  # Sets files to +files+, ensuring it is an array.

  def files=(files)
    @files = Array files
  end

  ##
  # Finds all gems that satisfy +dep+

  def find_all_satisfiers(dep)
    Gem::Specification.each do |spec|
      yield spec if spec.satisfies_requirement? dep
    end
  end

  private :find_all_satisfiers

  ##
  # Creates a duplicate spec without large blobs that aren't used at runtime.

  def for_cache
    spec = dup

    spec.files = nil
    spec.test_files = nil

    spec
  end

  def full_name
    @full_name ||= super
  end

  ##
  # Work around bundler removing my methods

  def gem_dir # :nodoc:
    super
  end

  def gems_dir
    @gems_dir ||= File.join(base_dir, "gems")
  end

  ##
  # Deprecated and ignored, defaults to true.
  #
  # Formerly used to indicate this gem was RDoc-capable.

  def has_rdoc # :nodoc:
    true
  end
  rubygems_deprecate :has_rdoc

  ##
  # Deprecated and ignored.
  #
  # Formerly used to indicate this gem was RDoc-capable.

  def has_rdoc=(ignored) # :nodoc:
    @has_rdoc = true
  end
  rubygems_deprecate :has_rdoc=

  alias :has_rdoc? :has_rdoc # :nodoc:
  rubygems_deprecate :has_rdoc?

  ##
  # True if this gem has files in test_files

  def has_unit_tests? # :nodoc:
    !test_files.empty?
  end

  # :stopdoc:
  alias has_test_suite? has_unit_tests?
  # :startdoc:

  def hash # :nodoc:
    name.hash ^ version.hash
  end

  def init_with(coder) # :nodoc:
    @installed_by_version ||= nil
    yaml_initialize coder.tag, coder.map
  end

  eval <<-RUBY, binding, __FILE__, __LINE__ + 1
    # frozen_string_literal: true

    def set_nil_attributes_to_nil
      #{@@nil_attributes.map {|key| "@#{key} = nil" }.join "; "}
    end
    private :set_nil_attributes_to_nil

    def set_not_nil_attributes_to_default_values
      #{@@non_nil_attributes.map {|key| "@#{key} = #{INITIALIZE_CODE_FOR_DEFAULTS[key]}" }.join ";"}
    end
    private :set_not_nil_attributes_to_default_values
  RUBY

  ##
  # Specification constructor. Assigns the default values to the attributes
  # and yields itself for further initialization.  Optionally takes +name+ and
  # +version+.

  def initialize(name = nil, version = nil)
    super()
    @gems_dir              = nil
    @base_dir              = nil
    @loaded = false
    @activated = false
    @loaded_from = nil
    @original_platform = nil
    @installed_by_version = nil

    set_nil_attributes_to_nil
    set_not_nil_attributes_to_default_values

    @new_platform = Gem::Platform::RUBY

    self.name = name if name
    self.version = version if version

    if (platform = Gem.platforms.last) && platform != Gem::Platform::RUBY && platform != Gem::Platform.local
      self.platform = platform
    end

    yield self if block_given?
  end

  ##
  # Duplicates array_attributes from +other_spec+ so state isn't shared.

  def initialize_copy(other_spec)
    self.class.array_attributes.each do |name|
      name = :"@#{name}"
      next unless other_spec.instance_variable_defined? name

      begin
        val = other_spec.instance_variable_get(name)
        if val
          instance_variable_set name, val.dup
        elsif Gem.configuration.really_verbose
          warn "WARNING: #{full_name} has an invalid nil value for #{name}"
        end
      rescue TypeError
        e = Gem::FormatException.new \
          "#{full_name} has an invalid value for #{name}"

        e.file_path = loaded_from
        raise e
      end
    end
  end

  def base_dir
    return Gem.dir unless loaded_from
    @base_dir ||= if default_gem?
      File.dirname File.dirname File.dirname loaded_from
    else
      File.dirname File.dirname loaded_from
    end
  end

  ##
  # Expire memoized instance variables that can incorrectly generate, replace
  # or miss files due changes in certain attributes used to compute them.

  def invalidate_memoized_attributes
    @full_name = nil
    @cache_file = nil
  end

  private :invalidate_memoized_attributes

  def inspect # :nodoc:
    if $DEBUG
      super
    else
      "#{super[0..-2]} #{full_name}>"
    end
  end

  ##
  # Files in the Gem under one of the require_paths

  def lib_files
    @files.select do |file|
      require_paths.any? do |path|
        file.start_with? path
      end
    end
  end

  ##
  # Singular accessor for #licenses

  def license
    licenses.first
  end

  ##
  # Plural accessor for setting licenses
  #
  # See #license= for details

  def licenses
    @licenses ||= []
  end

  def internal_init # :nodoc:
    super
    @bin_dir       = nil
    @cache_dir     = nil
    @cache_file    = nil
    @doc_dir       = nil
    @ri_dir        = nil
    @spec_dir      = nil
    @spec_file     = nil
  end

  ##
  # Sets the rubygems_version to the current RubyGems version.

  def mark_version
    @rubygems_version = Gem::VERSION
  end

  ##
  # Track removed method calls to warn about during build time.
  # Warn about unknown attributes while loading a spec.

  def method_missing(sym, *a, &b) # :nodoc:
    if REMOVED_METHODS.include?(sym)
      removed_method_calls << sym
      return
    end

    if @specification_version > CURRENT_SPECIFICATION_VERSION &&
       sym.to_s.end_with?("=")
      warn "ignoring #{sym} loading #{full_name}" if $DEBUG
    else
      super
    end
  end

  ##
  # Is this specification missing its extensions?  When this returns true you
  # probably want to build_extensions

  def missing_extensions?
    return false if extensions.empty?
    return false if default_gem?
    return false if File.exist? gem_build_complete_path

    true
  end

  ##
  # Normalize the list of files so that:
  # * All file lists have redundancies removed.
  # * Files referenced in the extra_rdoc_files are included in the package
  #   file list.

  def normalize
    if defined?(@extra_rdoc_files) && @extra_rdoc_files
      @extra_rdoc_files.uniq!
      @files ||= []
      @files.concat(@extra_rdoc_files)
    end

    @files            = @files.uniq if @files
    @extensions       = @extensions.uniq if @extensions
    @test_files       = @test_files.uniq if @test_files
    @executables      = @executables.uniq if @executables
    @extra_rdoc_files = @extra_rdoc_files.uniq if @extra_rdoc_files
  end

  ##
  # Return a NameTuple that represents this Specification

  def name_tuple
    Gem::NameTuple.new name, version, original_platform
  end

  ##
  # Returns the full name (name-version) of this gemspec using the original
  # platform.  For use with legacy gems.

  def original_name # :nodoc:
    if platform == Gem::Platform::RUBY || platform.nil?
      "#{@name}-#{@version}"
    else
      "#{@name}-#{@version}-#{@original_platform}"
    end
  end

  ##
  # Cruft. Use +platform+.

  def original_platform # :nodoc:
    @original_platform ||= platform
  end

  ##
  # The platform this gem runs on.  See Gem::Platform for details.

  def platform
    @new_platform ||= Gem::Platform::RUBY
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "Gem::Specification.new do |s|", "end" do
      q.breakable

      attributes = @@attributes - [:name, :version]
      attributes.unshift :installed_by_version
      attributes.unshift :version
      attributes.unshift :name

      attributes.each do |attr_name|
        current_value = self.send attr_name
        current_value = current_value.sort if %i[files test_files].include? attr_name
        if current_value != default_value(attr_name) ||
           self.class.required_attribute?(attr_name)

          q.text "s.#{attr_name} = "

          if attr_name == :date
            current_value = current_value.utc

            q.text "Time.utc(#{current_value.year}, #{current_value.month}, #{current_value.day})"
          else
            q.pp current_value
          end

          q.breakable
        end
      end
    end
  end

  ##
  # Raise an exception if the version of this spec conflicts with the one
  # that is already loaded (+other+)

  def check_version_conflict(other) # :nodoc:
    return if self.version == other.version

    # This gem is already loaded.  If the currently loaded gem is not in the
    # list of candidate gems, then we have a version conflict.

    msg = "can't activate #{full_name}, already activated #{other.full_name}"

    e = Gem::LoadError.new msg
    e.name = self.name

    raise e
  end

  private :check_version_conflict

  ##
  # Check the spec for possible conflicts and freak out if there are any.

  def raise_if_conflicts # :nodoc:
    if has_conflicts?
      raise Gem::ConflictError.new self, conflicts
    end
  end

  ##
  # Sets rdoc_options to +value+, ensuring it is an array.

  def rdoc_options=(options)
    @rdoc_options = Array options
  end

  ##
  # Singular accessor for #require_paths

  def require_path
    (val = require_paths) && val.first
  end

  ##
  # Singular accessor for #require_paths

  def require_path=(path)
    self.require_paths = Array(path)
  end

  ##
  # Set requirements to +req+, ensuring it is an array.

  def requirements=(req)
    @requirements = Array req
  end

  def respond_to_missing?(m, include_private = false) # :nodoc:
    false
  end

  ##
  # Returns the full path to this spec's ri directory.

  def ri_dir
    @ri_dir ||= File.join base_dir, "ri", full_name
  end

  ##
  # Return a string containing a Ruby code representation of the given
  # object.

  def ruby_code(obj)
    case obj
    when String             then obj.dump + ".freeze"
    when Array              then "[" + obj.map {|x| ruby_code x }.join(", ") + "]"
    when Hash               then
      seg = obj.keys.sort.map {|k| "#{k.to_s.dump} => #{obj[k].to_s.dump}" }
      "{ #{seg.join(', ')} }"
    when Gem::Version       then obj.to_s.dump
    when DateLike           then obj.strftime("%Y-%m-%d").dump
    when Time               then obj.strftime("%Y-%m-%d").dump
    when Numeric            then obj.inspect
    when true, false, nil   then obj.inspect
    when Gem::Platform      then "Gem::Platform.new(#{obj.to_a.inspect})"
    when Gem::Requirement   then
      list = obj.as_list
      "Gem::Requirement.new(#{ruby_code(list.size == 1 ? obj.to_s : list)})"
    else raise Gem::Exception, "ruby_code case not handled: #{obj.class}"
    end
  end

  private :ruby_code

  ##
  # List of dependencies that will automatically be activated at runtime.

  def runtime_dependencies
    dependencies.select(&:runtime?)
  end

  ##
  # True if this gem has the same attributes as +other+.

  def same_attributes?(spec)
    @@attributes.all? {|name, default| self.send(name) == spec.send(name) }
  end

  private :same_attributes?

  ##
  # Checks if this specification meets the requirement of +dependency+.

  def satisfies_requirement?(dependency)
    return @name == dependency.name &&
           dependency.requirement.satisfied_by?(@version)
  end

  ##
  # Returns an object you can use to sort specifications in #sort_by.

  def sort_obj
    [@name, @version, Gem::Platform.sort_priority(@new_platform)]
  end

  ##
  # Used by Gem::Resolver to order Gem::Specification objects

  def source # :nodoc:
    Gem::Source::Installed.new
  end

  ##
  # Returns the full path to the directory containing this spec's
  # gemspec file. eg: /usr/local/lib/ruby/gems/1.8/specifications

  def spec_dir
    @spec_dir ||= File.join base_dir, "specifications"
  end

  ##
  # Returns the full path to this spec's gemspec file.
  # eg: /usr/local/lib/ruby/gems/1.8/specifications/mygem-1.0.gemspec

  def spec_file
    @spec_file ||= File.join spec_dir, "#{full_name}.gemspec"
  end

  ##
  # The default name of the gemspec.  See also #file_name
  #
  #   spec.spec_name # => "example-1.0.gemspec"

  def spec_name
    "#{full_name}.gemspec"
  end

  ##
  # A short summary of this gem's description.

  def summary=(str)
    @summary = str.to_s.strip.
      gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').gsub(/\n[ \t]*/, " ") # so. weird.
  end

  ##
  # Singular accessor for #test_files

  def test_file # :nodoc:
    (val = test_files) && val.first
  end

  ##
  # Singular mutator for #test_files

  def test_file=(file) # :nodoc:
    self.test_files = [file]
  end

  ##
  # Test files included in this gem.  You cannot append to this accessor, you
  # must assign to it.

  def test_files # :nodoc:
    # Handle the possibility that we have @test_suite_file but not
    # @test_files.  This will happen when an old gem is loaded via
    # YAML.
    if defined? @test_suite_file
      @test_files = [@test_suite_file].flatten
      @test_suite_file = nil
    end
    if defined?(@test_files) && @test_files
      @test_files
    else
      @test_files = []
    end
  end

  ##
  # Returns a Ruby code representation of this specification, such that it can
  # be eval'ed and reconstruct the same specification later.  Attributes that
  # still have their default values are omitted.

  def to_ruby
    mark_version
    result = []
    result << "# -*- encoding: utf-8 -*-"
    result << "#{Gem::StubSpecification::PREFIX}#{name} #{version} #{platform} #{raw_require_paths.join("\0")}"
    result << "#{Gem::StubSpecification::PREFIX}#{extensions.join "\0"}" unless
      extensions.empty?
    result << nil
    result << "Gem::Specification.new do |s|"

    result << "  s.name = #{ruby_code name}"
    result << "  s.version = #{ruby_code version}"
    unless platform.nil? || platform == Gem::Platform::RUBY
      result << "  s.platform = #{ruby_code original_platform}"
    end
    result << ""
    result << "  s.required_rubygems_version = #{ruby_code required_rubygems_version} if s.respond_to? :required_rubygems_version="

    if metadata && !metadata.empty?
      result << "  s.metadata = #{ruby_code metadata} if s.respond_to? :metadata="
    end
    result << "  s.require_paths = #{ruby_code raw_require_paths}"

    handled = [
      :dependencies,
      :name,
      :platform,
      :require_paths,
      :required_rubygems_version,
      :specification_version,
      :version,
      :has_rdoc,
      :default_executable,
      :metadata,
      :signing_key,
    ]

    @@attributes.each do |attr_name|
      next if handled.include? attr_name
      current_value = self.send(attr_name)
      if current_value != default_value(attr_name) || self.class.required_attribute?(attr_name)
        result << "  s.#{attr_name} = #{ruby_code current_value}"
      end
    end

    if String === signing_key
      result << "  s.signing_key = #{signing_key.dump}.freeze"
    end

    if @installed_by_version
      result << nil
      result << "  s.installed_by_version = \"#{Gem::VERSION}\" if s.respond_to? :installed_by_version"
    end

    unless dependencies.empty?
      result << nil
      result << "  if s.respond_to? :specification_version then"
      result << "    s.specification_version = #{specification_version}"
      result << "  end"
      result << nil

      result << "  if s.respond_to? :add_runtime_dependency then"

      dependencies.each do |dep|
        req = dep.requirements_list.inspect
        dep.instance_variable_set :@type, :runtime if dep.type.nil? # HACK
        result << "    s.add_#{dep.type}_dependency(%q<#{dep.name}>.freeze, #{req})"
      end

      result << "  else"
      dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "    s.add_dependency(%q<#{dep.name}>.freeze, #{version_reqs_param})"
      end
      result << "  end"
    end

    result << "end"
    result << nil

    result.join "\n"
  end

  ##
  # Returns a Ruby lighter-weight code representation of this specification,
  # used for indexing only.
  #
  # See #to_ruby.

  def to_ruby_for_cache
    for_cache.to_ruby
  end

  def to_s # :nodoc:
    "#<Gem::Specification name=#{@name} version=#{@version}>"
  end

  ##
  # Returns self

  def to_spec
    self
  end

  def to_yaml(opts = {}) # :nodoc:
    Gem.load_yaml

    # Because the user can switch the YAML engine behind our
    # back, we have to check again here to make sure that our
    # psych code was properly loaded, and load it if not.
    unless Gem.const_defined?(:NoAliasYAMLTree)
      require_relative "psych_tree"
    end

    builder = Gem::NoAliasYAMLTree.create
    builder << self
    ast = builder.tree

    require "stringio"
    io = StringIO.new
    io.set_encoding Encoding::UTF_8

    Psych::Visitors::Emitter.new(io).accept(ast)

    io.string.gsub(/ !!null \n/, " \n")
  end

  ##
  # Recursively walk dependencies of this spec, executing the +block+ for each
  # hop.

  def traverse(trail = [], visited = {}, &block)
    trail.push(self)
    begin
      dependencies.each do |dep|
        next unless dep.runtime?
        dep.matching_specs(true).each do |dep_spec|
          next if visited.has_key?(dep_spec)
          visited[dep_spec] = true
          trail.push(dep_spec)
          begin
            result = block[self, dep, dep_spec, trail]
          ensure
            trail.pop
          end
          unless result == :next
            spec_name = dep_spec.name
            dep_spec.traverse(trail, visited, &block) unless
              trail.any? {|s| s.name == spec_name }
          end
        end
      end
    ensure
      trail.pop
    end
  end

  ##
  # Checks that the specification contains all required fields, and does a
  # very basic sanity check.
  #
  # Raises InvalidSpecificationException if the spec does not pass the
  # checks..

  def validate(packaging = true, strict = false)
    normalize

    validation_policy = Gem::SpecificationPolicy.new(self)
    validation_policy.packaging = packaging
    validation_policy.validate(strict)
  end

  def keep_only_files_and_directories
    @executables.delete_if      {|x| File.directory?(File.join(@bindir, x)) }
    @extensions.delete_if       {|x| File.directory?(x) && !File.symlink?(x) }
    @extra_rdoc_files.delete_if {|x| File.directory?(x) && !File.symlink?(x) }
    @files.delete_if            {|x| File.directory?(x) && !File.symlink?(x) }
    @test_files.delete_if       {|x| File.directory?(x) && !File.symlink?(x) }
  end

  def validate_metadata
    Gem::SpecificationPolicy.new(self).validate_metadata
  end
  rubygems_deprecate :validate_metadata

  def validate_dependencies
    Gem::SpecificationPolicy.new(self).validate_dependencies
  end
  rubygems_deprecate :validate_dependencies

  def validate_permissions
    Gem::SpecificationPolicy.new(self).validate_permissions
  end
  rubygems_deprecate :validate_permissions

  ##
  # Set the version to +version+, potentially also setting
  # required_rubygems_version if +version+ indicates it is a
  # prerelease.

  def version=(version)
    @version = Gem::Version.create(version)
    return if @version.nil?

    # skip to set required_ruby_version when pre-released rubygems.
    # It caused to raise CircularDependencyError
    if @version.prerelease? && (@name.nil? || @name.strip != "rubygems")
      self.required_rubygems_version = "> 1.3.1"
    end
    invalidate_memoized_attributes

    return @version
  end

  def stubbed?
    false
  end

  def yaml_initialize(tag, vals) # :nodoc:
    vals.each do |ivar, val|
      case ivar
      when "date"
        # Force Date to go through the extra coerce logic in date=
        self.date = val.tap(&Gem::UNTAINT)
      else
        instance_variable_set "@#{ivar}", val.tap(&Gem::UNTAINT)
      end
    end

    @original_platform = @platform # for backwards compatibility
    self.platform = Gem::Platform.new @platform
  end

  ##
  # Reset nil attributes to their default values to make the spec valid

  def reset_nil_attributes_to_default
    nil_attributes = self.class.non_nil_attributes.find_all do |name|
      !instance_variable_defined?("@#{name}") || instance_variable_get("@#{name}").nil?
    end

    nil_attributes.each do |attribute|
      default = self.default_value attribute

      value = case default
      when Time, Numeric, Symbol, true, false, nil then default
      else default.dup
      end

      instance_variable_set "@#{attribute}", value
    end

    @installed_by_version ||= nil
  end

  def flatten_require_paths # :nodoc:
    return unless raw_require_paths.first.is_a?(Array)

    warn "#{name} #{version} includes a gemspec with `require_paths` set to an array of arrays. Newer versions of this gem might've already fixed this"
    raw_require_paths.flatten!
  end

  def raw_require_paths # :nodoc:
    @require_paths
  end
end
