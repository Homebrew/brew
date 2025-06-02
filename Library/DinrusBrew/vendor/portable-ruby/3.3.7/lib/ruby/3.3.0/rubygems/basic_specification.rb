# frozen_string_literal: true

##
# BasicSpecification is an abstract class which implements some common code
# used by both Specification and StubSpecification.

class Gem::BasicSpecification
  ##
  # Allows installation of extensions for git: gems.

  attr_writer :base_dir # :nodoc:

  ##
  # Sets the directory where extensions for this gem will be installed.

  attr_writer :extension_dir # :nodoc:

  ##
  # Is this specification ignored for activation purposes?

  attr_writer :ignored # :nodoc:

  ##
  # The path this gemspec was loaded from.  This attribute is not persisted.

  attr_accessor :loaded_from

  ##
  # Allows correct activation of git: and path: gems.

  attr_writer :full_gem_path # :nodoc:

  def initialize
    internal_init
  end

  def self.default_specifications_dir
    Gem.default_specifications_dir
  end

  class << self
    extend Gem::Deprecate
    rubygems_deprecate :default_specifications_dir, "Gem.default_specifications_dir"
  end

  ##
  # The path to the gem.build_complete file within the extension install
  # directory.

  def gem_build_complete_path # :nodoc:
    File.join extension_dir, "gem.build_complete"
  end

  ##
  # True when the gem has been activated

  def activated?
    raise NotImplementedError
  end

  ##
  # Returns the full path to the base gem directory.
  #
  # eg: /usr/local/lib/ruby/gems/1.8

  def base_dir
    raise NotImplementedError
  end

  ##
  # Return true if this spec can require +file+.

  def contains_requirable_file?(file)
    if ignored?
      if platform == Gem::Platform::RUBY || Gem::Platform.local === platform
        warn "Ignoring #{full_name} because its extensions are not built. " \
             "Try: gem pristine #{name} --version #{version}"
      end

      return false
    end

    is_soext = file.end_with?(".so", ".o")

    if is_soext
      have_file? file.delete_suffix(File.extname(file)), Gem.dynamic_library_suffixes
    else
      have_file? file, Gem.suffixes
    end
  end

  ##
  # Return true if this spec should be ignored because it's missing extensions.

  def ignored?
    return @ignored unless @ignored.nil?

    @ignored = missing_extensions?
  end

  def default_gem?
    !loaded_from.nil? &&
      File.dirname(loaded_from) == Gem.default_specifications_dir
  end

  ##
  # Regular gems take precedence over default gems

  def default_gem_priority
    default_gem? ? 1 : -1
  end

  ##
  # Gems higher up in +gem_path+ take precedence

  def base_dir_priority(gem_path)
    gem_path.index(base_dir) || gem_path.size
  end

  ##
  # Returns full path to the directory where gem's extensions are installed.

  def extension_dir
    @extension_dir ||= File.expand_path(File.join(extensions_dir, full_name))
  end

  ##
  # Returns path to the extensions directory.

  def extensions_dir
    Gem.default_ext_dir_for(base_dir) ||
      File.join(base_dir, "extensions", Gem::Platform.local.to_s,
                Gem.extension_api_version)
  end

  def find_full_gem_path # :nodoc:
    # TODO: also, shouldn't it default to full_name if it hasn't been written?
    File.expand_path File.join(gems_dir, full_name)
  end

  private :find_full_gem_path

  ##
  # The full path to the gem (install path + full name).

  def full_gem_path
    # TODO: This is a heavily used method by gems, so we'll need
    # to aleast just alias it to #gem_dir rather than remove it.
    @full_gem_path ||= find_full_gem_path
  end

  ##
  # Returns the full name (name-version) of this Gem.  Platform information
  # is included (name-version-platform) if it is specified and not the
  # default Ruby platform.

  def full_name
    if platform == Gem::Platform::RUBY || platform.nil?
      "#{name}-#{version}"
    else
      "#{name}-#{version}-#{platform}"
    end
  end

  ##
  # Returns the full name of this Gem (see `Gem::BasicSpecification#full_name`).
  # Information about where the gem is installed is also included if not
  # installed in the default GEM_HOME.

  def full_name_with_location
    if base_dir != Gem.dir
      "#{full_name} in #{base_dir}"
    else
      full_name
    end
  end

  ##
  # Full paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.

  def full_require_paths
    @full_require_paths ||=
      begin
        full_paths = raw_require_paths.map do |path|
          File.join full_gem_path, path
        end

        full_paths << extension_dir if have_extensions?

        full_paths
      end
  end

  ##
  # The path to the data directory for this gem.

  def datadir
    # TODO: drop the extra ", gem_name" which is uselessly redundant
    File.expand_path(File.join(gems_dir, full_name, "data", name))
  end

  ##
  # Full path of the target library file.
  # If the file is not in this gem, return nil.

  def to_fullpath(path)
    if activated?
      @paths_map ||= {}
      Gem.suffixes.each do |suf|
        full_require_paths.each do |dir|
          fullpath = "#{dir}/#{path}#{suf}"
          next unless File.file?(fullpath)
          @paths_map[path] ||= fullpath
        end
      end
      @paths_map[path]
    end
  end

  ##
  # Returns the full path to this spec's gem directory.
  # eg: /usr/local/lib/ruby/1.8/gems/mygem-1.0

  def gem_dir
    @gem_dir ||= File.expand_path File.join(gems_dir, full_name)
  end

  ##
  # Returns the full path to the gems directory containing this spec's
  # gem directory. eg: /usr/local/lib/ruby/1.8/gems

  def gems_dir
    raise NotImplementedError
  end

  def internal_init # :nodoc:
    @extension_dir = nil
    @full_gem_path = nil
    @gem_dir = nil
    @ignored = nil
  end

  ##
  # Name of the gem

  def name
    raise NotImplementedError
  end

  ##
  # Platform of the gem

  def platform
    raise NotImplementedError
  end

  def raw_require_paths # :nodoc:
    raise NotImplementedError
  end

  ##
  # Paths in the gem to add to <code>$LOAD_PATH</code> when this gem is
  # activated.
  #
  # See also #require_paths=
  #
  # If you have an extension you do not need to add <code>"ext"</code> to the
  # require path, the extension build process will copy the extension files
  # into "lib" for you.
  #
  # The default value is <code>"lib"</code>
  #
  # Usage:
  #
  #   # If all library files are in the root directory...
  #   spec.require_path = '.'

  def require_paths
    return raw_require_paths unless have_extensions?

    [extension_dir].concat raw_require_paths
  end

  ##
  # Returns the paths to the source files for use with analysis and
  # documentation tools.  These paths are relative to full_gem_path.

  def source_paths
    paths = raw_require_paths.dup

    if have_extensions?
      ext_dirs = extensions.map do |extension|
        extension.split(File::SEPARATOR, 2).first
      end.uniq

      paths.concat ext_dirs
    end

    paths.uniq
  end

  ##
  # Return all files in this gem that match for +glob+.

  def matches_for_glob(glob) # TODO: rename?
    glob = File.join(lib_dirs_glob, glob)

    Dir[glob]
  end

  ##
  # Returns the list of plugins in this spec.

  def plugins
    matches_for_glob("rubygems#{Gem.plugin_suffix_pattern}")
  end

  ##
  # Returns a string usable in Dir.glob to match all requirable paths
  # for this spec.

  def lib_dirs_glob
    dirs = if raw_require_paths
      if raw_require_paths.size > 1
        "{#{raw_require_paths.join(",")}}"
      else
        raw_require_paths.first
      end
    else
      "lib" # default value for require_paths for bundler/inline
    end

    "#{full_gem_path}/#{dirs}"
  end

  ##
  # Return a Gem::Specification from this gem

  def to_spec
    raise NotImplementedError
  end

  ##
  # Version of the gem

  def version
    raise NotImplementedError
  end

  ##
  # Whether this specification is stubbed - i.e. we have information
  # about the gem from a stub line, without having to evaluate the
  # entire gemspec file.
  def stubbed?
    raise NotImplementedError
  end

  def this
    self
  end

  private

  def have_extensions?
    !extensions.empty?
  end

  def have_file?(file, suffixes)
    return true if raw_require_paths.any? do |path|
      base = File.join(gems_dir, full_name, path, file)
      suffixes.any? {|suf| File.file? base + suf }
    end

    if have_extensions?
      base = File.join extension_dir, file
      suffixes.any? {|suf| File.file? base + suf }
    else
      false
    end
  end
end
