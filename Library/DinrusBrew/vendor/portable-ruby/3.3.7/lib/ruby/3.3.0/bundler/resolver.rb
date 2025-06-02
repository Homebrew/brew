# frozen_string_literal: true

module Bundler
  #
  # This class implements the interface needed by PubGrub for resolution. It is
  # equivalent to the `PubGrub::BasicPackageSource` class provided by PubGrub by
  # default and used by the most simple PubGrub consumers.
  #
  class Resolver
    require_relative "vendored_pub_grub"
    require_relative "resolver/base"
    require_relative "resolver/candidate"
    require_relative "resolver/incompatibility"
    require_relative "resolver/root"

    include GemHelpers

    def initialize(base, gem_version_promoter)
      @source_requirements = base.source_requirements
      @base = base
      @gem_version_promoter = gem_version_promoter
    end

    def start
      @requirements = @base.requirements
      @packages = @base.packages

      root, logger = setup_solver

      Bundler.ui.info "Resolving dependencies...", true

      solve_versions(root: root, logger: logger)
    end

    def setup_solver
      root = Resolver::Root.new(name_for_explicit_dependency_source)
      root_version = Resolver::Candidate.new(0)

      @all_specs = Hash.new do |specs, name|
        source = source_for(name)
        matches = source.specs.search(name)

        # Don't bother to check for circular deps when no dependency API are
        # available, since it's too slow to be usable. That edge case won't work
        # but resolution other than that should work fine and reasonably fast.
        if source.respond_to?(:dependency_api_available?) && source.dependency_api_available?
          matches = filter_invalid_self_dependencies(matches, name)
        end

        specs[name] = matches.sort_by {|s| [s.version, s.platform.to_s] }
      end

      @all_versions = Hash.new do |candidates, package|
        candidates[package] = all_versions_for(package)
      end

      @sorted_versions = Hash.new do |candidates, package|
        candidates[package] = filtered_versions_for(package).sort
      end

      @sorted_versions[root] = [root_version]

      root_dependencies = prepare_dependencies(@requirements, @packages)

      @cached_dependencies = Hash.new do |dependencies, package|
        dependencies[package] = Hash.new do |versions, version|
          versions[version] = to_dependency_hash(version.dependencies.reject {|d| d.name == package.name }, @packages)
        end
      end

      @cached_dependencies[root] = { root_version => root_dependencies }

      logger = Bundler::UI::Shell.new
      logger.level = debug? ? "debug" : "warn"

      [root, logger]
    end

    def solve_versions(root:, logger:)
      solver = PubGrub::VersionSolver.new(source: self, root: root, logger: logger)
      result = solver.solve
      resolved_specs = result.map {|package, version| version.to_specs(package) }.flatten
      resolved_specs |= @base.specs_compatible_with(SpecSet.new(resolved_specs))
    rescue PubGrub::SolveFailure => e
      incompatibility = e.incompatibility

      names_to_unlock, names_to_allow_prereleases_for, names_to_allow_remote_specs_for, extended_explanation = find_names_to_relax(incompatibility)

      names_to_relax = names_to_unlock + names_to_allow_prereleases_for + names_to_allow_remote_specs_for

      if names_to_relax.any?
        if names_to_unlock.any?
          Bundler.ui.debug "Found conflicts with locked dependencies. Will retry with #{names_to_unlock.join(", ")} unlocked...", true

          @base.unlock_names(names_to_unlock)
        end

        if names_to_allow_prereleases_for.any?
          Bundler.ui.debug "Found conflicts with dependencies with prereleases. Will retry considering prereleases for #{names_to_allow_prereleases_for.join(", ")}...", true

          @base.include_prereleases(names_to_allow_prereleases_for)
        end

        if names_to_allow_remote_specs_for.any?
          Bundler.ui.debug "Found conflicts with local versions of #{names_to_allow_remote_specs_for.join(", ")}. Will retry considering remote versions...", true

          @base.include_remote_specs(names_to_allow_remote_specs_for)
        end

        root, logger = setup_solver

        Bundler.ui.debug "Retrying resolution...", true
        retry
      end

      explanation = e.message

      if extended_explanation
        explanation << "\n\n"
        explanation << extended_explanation
      end

      raise SolveFailure.new(explanation)
    end

    def find_names_to_relax(incompatibility)
      names_to_unlock = []
      names_to_allow_prereleases_for = []
      names_to_allow_remote_specs_for = []
      extended_explanation = nil

      while incompatibility.conflict?
        cause = incompatibility.cause
        incompatibility = cause.incompatibility

        incompatibility.terms.each do |term|
          package = term.package
          name = package.name

          if base_requirements[name]
            names_to_unlock << name
          elsif package.ignores_prereleases? && @all_specs[name].any? {|s| s.version.prerelease? }
            names_to_allow_prereleases_for << name
          elsif package.prefer_local? && @all_specs[name].any? {|s| !s.is_a?(StubSpecification) }
            names_to_allow_remote_specs_for << name
          end

          no_versions_incompat = [cause.incompatibility, cause.satisfier].find {|incompat| incompat.cause.is_a?(PubGrub::Incompatibility::NoVersions) }
          next unless no_versions_incompat

          extended_explanation = no_versions_incompat.extended_explanation
        end
      end

      [names_to_unlock.uniq, names_to_allow_prereleases_for.uniq, names_to_allow_remote_specs_for.uniq, extended_explanation]
    end

    def parse_dependency(package, dependency)
      range = if repository_for(package).is_a?(Source::Gemspec)
        PubGrub::VersionRange.any
      else
        requirement_to_range(dependency)
      end

      PubGrub::VersionConstraint.new(package, range: range)
    end

    def versions_for(package, range=VersionRange.any)
      versions = select_sorted_versions(package, range)

      # Conditional avoids (among other things) calling
      # sort_versions_by_preferred with the root package
      if versions.size > 1
        sort_versions_by_preferred(package, versions)
      else
        versions
      end
    end

    def no_versions_incompatibility_for(package, unsatisfied_term)
      cause = PubGrub::Incompatibility::NoVersions.new(unsatisfied_term)
      name = package.name
      constraint = unsatisfied_term.constraint
      constraint_string = constraint.constraint_string
      requirements = constraint_string.split(" OR ").map {|req| Gem::Requirement.new(req.split(",")) }

      if name == "bundler" && bundler_pinned_to_current_version?
        custom_explanation = "the current Bundler version (#{Bundler::VERSION}) does not satisfy #{constraint}"
        extended_explanation = bundler_not_found_message(requirements)
      else
        specs_matching_other_platforms = filter_matching_specs(@all_specs[name], requirements)

        platforms_explanation = specs_matching_other_platforms.any? ? " for any resolution platforms (#{package.platforms.join(", ")})" : ""
        custom_explanation = "#{constraint} could not be found in #{repository_for(package)}#{platforms_explanation}"

        label = "#{name} (#{constraint_string})"
        extended_explanation = other_specs_matching_message(specs_matching_other_platforms, label) if specs_matching_other_platforms.any?
      end

      Incompatibility.new([unsatisfied_term], cause: cause, custom_explanation: custom_explanation, extended_explanation: extended_explanation)
    end

    def debug?
      ENV["BUNDLER_DEBUG_RESOLVER"] ||
        ENV["BUNDLER_DEBUG_RESOLVER_TREE"] ||
        ENV["DEBUG_RESOLVER"] ||
        ENV["DEBUG_RESOLVER_TREE"] ||
        false
    end

    def incompatibilities_for(package, version)
      package_deps = @cached_dependencies[package]
      sorted_versions = @sorted_versions[package]
      package_deps[version].map do |dep_package, dep_constraint|
        low = high = sorted_versions.index(version)

        # find version low such that all >= low share the same dep
        while low > 0 && package_deps[sorted_versions[low - 1]][dep_package] == dep_constraint
          low -= 1
        end
        low =
          if low == 0
            nil
          else
            sorted_versions[low]
          end

        # find version high such that all < high share the same dep
        while high < sorted_versions.length && package_deps[sorted_versions[high]][dep_package] == dep_constraint
          high += 1
        end
        high =
          if high == sorted_versions.length
            nil
          else
            sorted_versions[high]
          end

        range = PubGrub::VersionRange.new(min: low, max: high, include_min: true)

        self_constraint = PubGrub::VersionConstraint.new(package, range: range)

        dep_term = PubGrub::Term.new(dep_constraint, false)
        self_term = PubGrub::Term.new(self_constraint, true)

        custom_explanation = if dep_package.meta? && package.root?
          "current #{dep_package} version is #{dep_constraint.constraint_string}"
        end

        PubGrub::Incompatibility.new([self_term, dep_term], cause: :dependency, custom_explanation: custom_explanation)
      end
    end

    def all_versions_for(package)
      name = package.name
      results = (@base[name] + filter_specs(@all_specs[name], package)).uniq {|spec| [spec.version.hash, spec.platform] }

      if name == "bundler" && !bundler_pinned_to_current_version?
        bundler_spec = Gem.loaded_specs["bundler"]
        results << bundler_spec if bundler_spec
      end

      locked_requirement = base_requirements[name]
      results = filter_matching_specs(results, locked_requirement) if locked_requirement

      results.group_by(&:version).reduce([]) do |groups, (version, specs)|
        platform_specs = package.platform_specs(specs)

        # If package is a top-level dependency,
        #   candidate is only valid if there are matching versions for all resolution platforms.
        #
        # If package is not a top-level deependency,
        #   then it's not necessary that it has matching versions for all platforms, since it may have been introduced only as
        #   a dependency for a platform specific variant, so it will only need to have a valid version for that platform.
        #
        if package.top_level?
          next groups if platform_specs.any?(&:empty?)
        else
          next groups if platform_specs.all?(&:empty?)
        end

        ruby_specs = select_best_platform_match(specs, Gem::Platform::RUBY)
        ruby_group = Resolver::SpecGroup.new(ruby_specs)

        unless ruby_group.empty?
          platform_specs.each do |specs|
            ruby_group.merge(Resolver::SpecGroup.new(specs))
          end

          groups << Resolver::Candidate.new(version, group: ruby_group, priority: -1)
          next groups if package.force_ruby_platform?
        end

        platform_group = Resolver::SpecGroup.new(platform_specs.flatten.uniq)
        next groups if platform_group == ruby_group

        groups << Resolver::Candidate.new(version, group: platform_group, priority: 1)

        groups
      end
    end

    def source_for(name)
      @source_requirements[name] || @source_requirements[:default]
    end

    def default_bundler_source
      @source_requirements[:default_bundler]
    end

    def bundler_pinned_to_current_version?
      !default_bundler_source.nil?
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue StandardError
      "Gemfile"
    end

    def raise_not_found!(package)
      name = package.name
      source = source_for(name)
      specs = @all_specs[name]
      matching_part = name
      requirement_label = SharedHelpers.pretty_dependency(package.dependency)
      cache_message = begin
                          " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                        rescue GemfileNotFound
                          nil
                        end
      specs_matching_requirement = filter_matching_specs(specs, package.dependency.requirement)

      not_found_message = if specs_matching_requirement.any?
        specs = specs_matching_requirement
        matching_part = requirement_label
        platforms = package.platforms

        if platforms.size == 1
          "Could not find gem '#{requirement_label}' with platform '#{platforms.first}'"
        else
          "Could not find gems matching '#{requirement_label}' valid for all resolution platforms (#{platforms.join(", ")})"
        end
      else
        "Could not find gem '#{requirement_label}'"
      end

      message = String.new("#{not_found_message} in #{source}#{cache_message}.\n")

      if specs.any?
        message << "\n#{other_specs_matching_message(specs, matching_part)}"
      end

      raise GemNotFound, message
    end

    private

    def filtered_versions_for(package)
      @gem_version_promoter.filter_versions(package, @all_versions[package])
    end

    def raise_all_versions_filtered_out!(package)
      level = @gem_version_promoter.level
      name = package.name
      locked_version = package.locked_version
      requirement = package.dependency

      raise GemNotFound,
        "#{name} is locked to #{locked_version}, while Gemfile is requesting #{requirement}. " \
        "--strict --#{level} was specified, but there are no #{level} level upgrades from #{locked_version} satisfying #{requirement}, so version solving has failed"
    end

    def filter_matching_specs(specs, requirements)
      Array(requirements).flat_map do |requirement|
        specs.select {| spec| requirement_satisfied_by?(requirement, spec) }
      end
    end

    def filter_specs(specs, package)
      filter_remote_specs(filter_prereleases(specs, package), package)
    end

    def filter_prereleases(specs, package)
      return specs unless package.ignores_prereleases? && specs.size > 1

      specs.reject {|s| s.version.prerelease? }
    end

    def filter_remote_specs(specs, package)
      return specs unless package.prefer_local?

      specs.select {|s| s.is_a?(StubSpecification) }
    end

    # Ignore versions that depend on themselves incorrectly
    def filter_invalid_self_dependencies(specs, name)
      specs.reject do |s|
        s.dependencies.any? {|d| d.name == name && !d.requirement.satisfied_by?(s.version) }
      end
    end

    def requirement_satisfied_by?(requirement, spec)
      requirement.satisfied_by?(spec.version) || spec.source.is_a?(Source::Gemspec)
    end

    def sort_versions_by_preferred(package, versions)
      @gem_version_promoter.sort_versions(package, versions)
    end

    def repository_for(package)
      source_for(package.name)
    end

    def base_requirements
      @base.base_requirements
    end

    def prepare_dependencies(requirements, packages)
      to_dependency_hash(requirements, packages).map do |dep_package, dep_constraint|
        name = dep_package.name

        next [dep_package, dep_constraint] if name == "bundler"

        dep_range = dep_constraint.range
        versions = select_sorted_versions(dep_package, dep_range)
        if versions.empty?
          if dep_package.ignores_prereleases? || dep_package.prefer_local?
            @all_versions.delete(dep_package)
            @sorted_versions.delete(dep_package)
          end
          dep_package.consider_prereleases! if dep_package.ignores_prereleases?
          dep_package.consider_remote_versions! if dep_package.prefer_local?
          versions = select_sorted_versions(dep_package, dep_range)
        end

        if versions.empty? && select_all_versions(dep_package, dep_range).any?
          raise_all_versions_filtered_out!(dep_package)
        end

        next [dep_package, dep_constraint] unless versions.empty?

        next unless dep_package.current_platform?

        raise_not_found!(dep_package)
      end.compact.to_h
    end

    def select_sorted_versions(package, range)
      range.select_versions(@sorted_versions[package])
    end

    def select_all_versions(package, range)
      range.select_versions(@all_versions[package])
    end

    def other_specs_matching_message(specs, requirement)
      message = String.new("The source contains the following gems matching '#{requirement}':\n")
      message << specs.map {|s| "  * #{s.full_name}" }.join("\n")
      message
    end

    def requirement_to_range(requirement)
      ranges = requirement.requirements.map do |(op, version)|
        ver = Resolver::Candidate.new(version, priority: -1)
        platform_ver = Resolver::Candidate.new(version, priority: 1)

        case op
        when "~>"
          name = "~> #{ver}"
          bump = Resolver::Candidate.new(version.bump.to_s + ".A")
          PubGrub::VersionRange.new(name: name, min: ver, max: bump, include_min: true)
        when ">"
          PubGrub::VersionRange.new(min: platform_ver)
        when ">="
          PubGrub::VersionRange.new(min: ver, include_min: true)
        when "<"
          PubGrub::VersionRange.new(max: ver)
        when "<="
          PubGrub::VersionRange.new(max: platform_ver, include_max: true)
        when "="
          PubGrub::VersionRange.new(min: ver, max: platform_ver, include_min: true, include_max: true)
        when "!="
          PubGrub::VersionRange.new(min: ver, max: platform_ver, include_min: true, include_max: true).invert
        else
          raise "bad version specifier: #{op}"
        end
      end

      ranges.inject(&:intersect)
    end

    def to_dependency_hash(dependencies, packages)
      dependencies.inject({}) do |deps, dep|
        package = packages[dep.name]

        current_req = deps[package]
        new_req = parse_dependency(package, dep.requirement)

        deps[package] = if current_req
          current_req.intersect(new_req)
        else
          new_req
        end

        deps
      end
    end

    def bundler_not_found_message(conflict_dependencies)
      candidate_specs = filter_matching_specs(default_bundler_source.specs.search("bundler"), conflict_dependencies)

      if candidate_specs.any?
        target_version = candidate_specs.last.version
        new_command = [File.basename($PROGRAM_NAME), "_#{target_version}_", *ARGV].join(" ")
        "Your bundle requires a different version of Bundler than the one you're running.\n" \
        "Install the necessary version with `gem install bundler:#{target_version}` and rerun bundler using `#{new_command}`\n"
      else
        "Your bundle requires a different version of Bundler than the one you're running, and that version could not be found.\n"
      end
    end
  end
end
