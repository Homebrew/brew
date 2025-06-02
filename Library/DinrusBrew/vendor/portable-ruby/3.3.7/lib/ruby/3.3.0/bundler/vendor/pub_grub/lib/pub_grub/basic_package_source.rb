require_relative 'version_constraint'
require_relative 'incompatibility'

module Bundler::PubGrub
  # Types:
  #
  # Where possible, Bundler::PubGrub will accept user-defined types, so long as they quack.
  #
  # ## "Package":
  #
  # This class will be used to represent the various packages being solved for.
  # .to_s will be called when displaying errors and debugging info, it should
  # probably return the package's name.
  # It must also have a reasonable definition of #== and #hash
  #
  # Example classes: String ("rails")
  #
  #
  # ## "Version":
  #
  # This class will be used to represent a single version number.
  #
  # Versions don't need to store their associated package, however they will
  # only be compared against other versions of the same package.
  #
  # It must be Comparible (and implement <=> reasonably)
  #
  # Example classes: Gem::Version, Integer
  #
  #
  # ## "Dependency"
  #
  # This class represents the requirement one package has on another. It is
  # returned by dependencies_for(package, version) and will be passed to
  # parse_dependency to convert it to a format Bundler::PubGrub understands.
  #
  # It must also have a reasonable definition of #==
  #
  # Example classes: String ("~> 1.0"), Gem::Requirement
  #
  class BasicPackageSource
    # Override me!
    #
    # This is called per package to find all possible versions of a package.
    #
    # It is called at most once per-package
    #
    # Returns: Array of versions for a package, in preferred order of selection
    def all_versions_for(package)
      raise NotImplementedError
    end

    # Override me!
    #
    # Returns: Hash in the form of { package => requirement, ... }
    def dependencies_for(package, version)
      raise NotImplementedError
    end

    # Override me!
    #
    # Convert a (user-defined) dependency into a format Bundler::PubGrub understands.
    #
    # Package is passed to this method but for many implementations is not
    # needed.
    #
    # Returns: either a Bundler::PubGrub::VersionRange, Bundler::PubGrub::VersionUnion, or a
    #   Bundler::PubGrub::VersionConstraint
    def parse_dependency(package, dependency)
      raise NotImplementedError
    end

    # Override me!
    #
    # If not overridden, this will call dependencies_for with the root package.
    #
    # Returns: Hash in the form of { package => requirement, ... } (see dependencies_for)
    def root_dependencies
      dependencies_for(@root_package, @root_version)
    end

    # Override me (maybe)
    #
    # If not overridden, the order returned by all_versions_for will be used
    #
    # Returns: Array of versions in preferred order
    def sort_versions_by_preferred(package, sorted_versions)
      indexes = @version_indexes[package]
      sorted_versions.sort_by { |version| indexes[version] }
    end

    def initialize
      @root_package = Package.root
      @root_version = Package.root_version

      @cached_versions = Hash.new do |h,k|
        if k == @root_package
          h[k] = [@root_version]
        else
          h[k] = all_versions_for(k)
        end
      end
      @sorted_versions = Hash.new { |h,k| h[k] = @cached_versions[k].sort }
      @version_indexes = Hash.new { |h,k| h[k] = @cached_versions[k].each.with_index.to_h }

      @cached_dependencies = Hash.new do |packages, package|
        if package == @root_package
          packages[package] = {
            @root_version => root_dependencies
          }
        else
          packages[package] = Hash.new do |versions, version|
            versions[version] = dependencies_for(package, version)
          end
        end
      end
    end

    def versions_for(package, range=VersionRange.any)
      versions = range.select_versions(@sorted_versions[package])

      # Conditional avoids (among other things) calling
      # sort_versions_by_preferred with the root package
      if versions.size > 1
        sort_versions_by_preferred(package, versions)
      else
        versions
      end
    end

    def no_versions_incompatibility_for(_package, unsatisfied_term)
      cause = Incompatibility::NoVersions.new(unsatisfied_term)

      Incompatibility.new([unsatisfied_term], cause: cause)
    end

    def incompatibilities_for(package, version)
      package_deps = @cached_dependencies[package]
      sorted_versions = @sorted_versions[package]
      package_deps[version].map do |dep_package, dep_constraint_name|
        low = high = sorted_versions.index(version)

        # find version low such that all >= low share the same dep
        while low > 0 &&
            package_deps[sorted_versions[low - 1]][dep_package] == dep_constraint_name
          low -= 1
        end
        low =
          if low == 0
            nil
          else
            sorted_versions[low]
          end

        # find version high such that all < high share the same dep
        while high < sorted_versions.length &&
            package_deps[sorted_versions[high]][dep_package] == dep_constraint_name
          high += 1
        end
        high =
          if high == sorted_versions.length
            nil
          else
            sorted_versions[high]
          end

        range = VersionRange.new(min: low, max: high, include_min: true)

        self_constraint = VersionConstraint.new(package, range: range)

        if !@packages.include?(dep_package)
          # no such package -> this version is invalid
        end

        dep_constraint = parse_dependency(dep_package, dep_constraint_name)
        if !dep_constraint
          # falsey indicates this dependency was invalid
          cause = Bundler::PubGrub::Incompatibility::InvalidDependency.new(dep_package, dep_constraint_name)
          return [Incompatibility.new([Term.new(self_constraint, true)], cause: cause)]
        elsif !dep_constraint.is_a?(VersionConstraint)
          # Upgrade range/union to VersionConstraint
          dep_constraint = VersionConstraint.new(dep_package, range: dep_constraint)
        end

        Incompatibility.new([Term.new(self_constraint, true), Term.new(dep_constraint, false)], cause: :dependency)
      end
    end
  end
end
