# frozen_string_literal: true
##
# A VendorSet represents gems that have been unpacked into a specific
# directory that contains a gemspec.
#
# This is used for gem dependency file support.
#
# Example:
#
#   set = Gem::Resolver::VendorSet.new
#
#   set.add_vendor_gem 'rake', 'vendor/rake'
#
# The directory vendor/rake must contain an unpacked rake gem along with a
# rake.gemspec (watching the given name).

class Gem::Resolver::VendorSet < Gem::Resolver::Set
  ##
  # The specifications for this set.

  attr_reader :specs # :nodoc:

  def initialize # :nodoc:
    super()

    @directories = {}
    @specs       = {}
  end

  ##
  # Adds a specification to the set with the given +name+ which has been
  # unpacked into the given +directory+.

  def add_vendor_gem(name, directory) # :nodoc:
    gemspec = File.join directory, "#{name}.gemspec"

    spec = Gem::Specification.load gemspec

    raise Gem::GemNotFoundException,
          "unable to find #{gemspec} for gem #{name}" unless spec

    spec.full_gem_path = File.expand_path directory

    @specs[spec.name]  = spec
    @directories[spec] = directory

    spec
  end

  ##
  # Returns an Array of VendorSpecification objects matching the
  # DependencyRequest +req+.

  def find_all(req)
    @specs.values.select do |spec|
      req.match? spec
    end.map do |spec|
      source = Gem::Source::Vendor.new @directories[spec]
      Gem::Resolver::VendorSpecification.new self, spec, source
    end
  end

  ##
  # Loads a spec with the given +name+. +version+, +platform+ and +source+ are
  # ignored.

  def load_spec(name, version, platform, source) # :nodoc:
    @specs.fetch name
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[VendorSet", "]" do
      next if @directories.empty?
      q.breakable

      dirs = @directories.map do |spec, directory|
        "#{spec.full_name}: #{directory}"
      end

      q.seplist dirs do |dir|
        q.text dir
      end
    end
  end
end
