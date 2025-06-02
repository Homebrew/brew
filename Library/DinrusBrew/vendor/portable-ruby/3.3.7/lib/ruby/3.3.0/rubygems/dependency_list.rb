# frozen_string_literal: true

#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require_relative "vendored_tsort"
require_relative "deprecate"

##
# Gem::DependencyList is used for installing and uninstalling gems in the
# correct order to avoid conflicts.
#--
# TODO: It appears that all but topo-sort functionality is being duplicated
# (or is planned to be duplicated) elsewhere in rubygems.  Is the majority of
# this class necessary anymore?  Especially #ok?, #why_not_ok?

class Gem::DependencyList
  attr_reader :specs

  include Enumerable
  include Gem::TSort

  ##
  # Allows enabling/disabling use of development dependencies

  attr_accessor :development

  ##
  # Creates a DependencyList from the current specs.

  def self.from_specs
    list = new
    list.add(*Gem::Specification.to_a)
    list
  end

  ##
  # Creates a new DependencyList.  If +development+ is true, development
  # dependencies will be included.

  def initialize(development = false)
    @specs = []

    @development = development
  end

  ##
  # Adds +gemspecs+ to the dependency list.

  def add(*gemspecs)
    @specs.concat gemspecs
  end

  def clear
    @specs.clear
  end

  ##
  # Return a list of the gem specifications in the dependency list, sorted in
  # order so that no gemspec in the list depends on a gemspec earlier in the
  # list.
  #
  # This is useful when removing gems from a set of installed gems.  By
  # removing them in the returned order, you don't get into as many dependency
  # issues.
  #
  # If there are circular dependencies (yuck!), then gems will be returned in
  # order until only the circular dependents and anything they reference are
  # left.  Then arbitrary gemspecs will be returned until the circular
  # dependency is broken, after which gems will be returned in dependency
  # order again.

  def dependency_order
    sorted = strongly_connected_components.flatten

    result = []
    seen = {}

    sorted.each do |spec|
      if index = seen[spec.name]
        if result[index].version < spec.version
          result[index] = spec
        end
      else
        seen[spec.name] = result.length
        result << spec
      end
    end

    result.reverse
  end

  ##
  # Iterator over dependency_order

  def each(&block)
    dependency_order.each(&block)
  end

  def find_name(full_name)
    @specs.find {|spec| spec.full_name == full_name }
  end

  def inspect # :nodoc:
    format("%s %p>", super[0..-2], map(&:full_name))
  end

  ##
  # Are all the dependencies in the list satisfied?

  def ok?
    why_not_ok?(:quick).empty?
  end

  def why_not_ok?(quick = false)
    unsatisfied = Hash.new {|h,k| h[k] = [] }
    each do |spec|
      spec.runtime_dependencies.each do |dep|
        inst = Gem::Specification.any? do |installed_spec|
          dep.name == installed_spec.name &&
            dep.requirement.satisfied_by?(installed_spec.version)
        end

        unless inst || @specs.find {|s| s.satisfies_requirement? dep }
          unsatisfied[spec.name] << dep
          return unsatisfied if quick
        end
      end
    end

    unsatisfied
  end

  ##
  # It is ok to remove a gemspec from the dependency list?
  #
  # If removing the gemspec creates breaks a currently ok dependency, then it
  # is NOT ok to remove the gemspec.

  def ok_to_remove?(full_name, check_dev=true)
    gem_to_remove = find_name full_name

    # If the state is inconsistent, at least don't crash
    return true unless gem_to_remove

    siblings = @specs.find_all do |s|
      s.name == gem_to_remove.name &&
        s.full_name != gem_to_remove.full_name
    end

    deps = []

    @specs.each do |spec|
      check = check_dev ? spec.dependencies : spec.runtime_dependencies

      check.each do |dep|
        deps << dep if gem_to_remove.satisfies_requirement?(dep)
      end
    end

    deps.all? do |dep|
      siblings.any? do |s|
        s.satisfies_requirement? dep
      end
    end
  end

  ##
  # Remove everything in the DependencyList that matches but doesn't
  # satisfy items in +dependencies+ (a hash of gem names to arrays of
  # dependencies).

  def remove_specs_unsatisfied_by(dependencies)
    specs.reject! do |spec|
      dep = dependencies[spec.name]
      dep && !dep.requirement.satisfied_by?(spec.version)
    end
  end

  ##
  # Removes the gemspec matching +full_name+ from the dependency list

  def remove_by_name(full_name)
    @specs.delete_if {|spec| spec.full_name == full_name }
  end

  ##
  # Return a hash of predecessors.  <tt>result[spec]</tt> is an Array of
  # gemspecs that have a dependency satisfied by the named gemspec.

  def spec_predecessors
    result = Hash.new {|h,k| h[k] = [] }

    specs = @specs.sort.reverse

    specs.each do |spec|
      specs.each do |other|
        next if spec == other

        other.dependencies.each do |dep|
          if spec.satisfies_requirement? dep
            result[spec] << other
          end
        end
      end
    end

    result
  end

  def tsort_each_node(&block)
    @specs.each(&block)
  end

  def tsort_each_child(node)
    specs = @specs.sort.reverse

    dependencies = node.runtime_dependencies
    dependencies.push(*node.development_dependencies) if @development

    dependencies.each do |dep|
      specs.each do |spec|
        if spec.satisfies_requirement? dep
          yield spec
          break
        end
      end
    end
  end

  private

  ##
  # Count the number of gemspecs in the list +specs+ that are not in
  # +ignored+.

  def active_count(specs, ignored)
    specs.count {|spec| ignored[spec.full_name].nil? }
  end
end
