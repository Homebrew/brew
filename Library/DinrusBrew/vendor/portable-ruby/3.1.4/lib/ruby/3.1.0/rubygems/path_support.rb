# frozen_string_literal: true
##
#
# Gem::PathSupport facilitates the GEM_HOME and GEM_PATH environment settings
# to the rest of RubyGems.
#
class Gem::PathSupport
  ##
  # The default system path for managing Gems.
  attr_reader :home

  ##
  # Array of paths to search for Gems.
  attr_reader :path

  ##
  # Directory with spec cache
  attr_reader :spec_cache_dir # :nodoc:

  ##
  #
  # Constructor. Takes a single argument which is to be treated like a
  # hashtable, or defaults to ENV, the system environment.
  #
  def initialize(env)
    @home = env["GEM_HOME"] || Gem.default_dir

    if File::ALT_SEPARATOR
      @home = @home.gsub(File::ALT_SEPARATOR, File::SEPARATOR)
    end

    @home = expand(@home)

    @path = split_gem_path env["GEM_PATH"], @home

    @spec_cache_dir = env["GEM_SPEC_CACHE"] || Gem.default_spec_cache_dir

    @spec_cache_dir = @spec_cache_dir.dup.tap(&Gem::UNTAINT)
  end

  private

  ##
  # Split the Gem search path (as reported by Gem.path).

  def split_gem_path(gpaths, home)
    # FIX: it should be [home, *path], not [*path, home]

    gem_path = []

    if gpaths
      gem_path = gpaths.split(Gem.path_separator)
      # Handle the path_separator being set to a regexp, which will cause
      # end_with? to error
      if gpaths =~ /#{Gem.path_separator}\z/
        gem_path += default_path
      end

      if File::ALT_SEPARATOR
        gem_path.map! do |this_path|
          this_path.gsub File::ALT_SEPARATOR, File::SEPARATOR
        end
      end

      gem_path << home
    else
      gem_path = default_path
    end

    gem_path.map {|path| expand(path) }.uniq
  end

  # Return the default Gem path
  def default_path
    Gem.default_path + [@home]
  end

  def expand(path)
    if File.directory?(path)
      File.realpath(path)
    else
      path
    end
  end
end
