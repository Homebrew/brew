# frozen_string_literal: true

module Bundler
  class Resolver
    require_relative "vendored_molinillo"
    require_relative "resolver/base"
    require_relative "resolver/spec_group"

    include GemHelpers

    def initialize(source_requirements, base, gem_version_promoter, additional_base_requirements, platforms)
      @source_requirements = source_requirements
      @base = Resolver::Base.new(base, additional_base_requirements)
      @resolver = Molinillo::Resolver.new(self, self)
      @results_for = {}
      @search_for = {}
      @platforms = platforms
      @resolving_only_for_ruby = platforms == [Gem::Platform::RUBY]
      @gem_version_promoter = gem_version_promoter
    end

    def start(requirements, exclude_specs: [])
      @metadata_requirements, regular_requirements = requirements.partition {|dep| dep.name.end_with?("\0") }

      exclude_specs.each do |spec|
        remove_from_candidates(spec)
      end

      requirements.each {|dep| prerelease_specified[dep.name] ||= dep.prerelease? }

      verify_gemfile_dependencies_are_found!(requirements)
      result = @resolver.resolve(requirements).
        map(&:payload).
        reject {|sg| sg.name.end_with?("\0") }.
        map(&:to_specs).
        flatten

      SpecSet.new(SpecSet.new(result).for(regular_requirements, false, @platforms))
    rescue Molinillo::VersionConflict => e
      conflicts = e.conflicts

      deps_to_unlock = conflicts.values.inject([]) do |deps, conflict|
        deps |= conflict.requirement_trees.flatten.map {|req| base_requirements[req.name] }.compact
      end

      if deps_to_unlock.any?
        @base.unlock_deps(deps_to_unlock)
        reset_spec_cache
        retry
      end

      message = version_conflict_message(e)
      raise VersionConflict.new(conflicts.keys.uniq, message)
    rescue Molinillo::CircularDependencyError => e
      names = e.dependencies.sort_by(&:name).map {|d| "gem '#{d.name}'" }
      raise CyclicDependencyError, "Your bundle requires gems that depend" \
        " on each other, creating an infinite loop. Please remove" \
        " #{names.count > 1 ? "either " : ""}#{names.join(" or ")}" \
        " and try again."
    end

    include Molinillo::UI

    # Conveys debug information to the user.
    #
    # @param [Integer] depth the current depth of the resolution process.
    # @return [void]
    def debug(depth = 0)
      return unless debug?
      debug_info = yield
      debug_info = debug_info.inspect unless debug_info.is_a?(String)
      puts debug_info.split("\n").map {|s| depth == 0 ? "BUNDLER: #{s}" : "BUNDLER(#{depth}): #{s}" }
    end

    def debug?
      return @debug_mode if defined?(@debug_mode)
      @debug_mode =
        ENV["BUNDLER_DEBUG_RESOLVER"] ||
        ENV["BUNDLER_DEBUG_RESOLVER_TREE"] ||
        ENV["DEBUG_RESOLVER"] ||
        ENV["DEBUG_RESOLVER_TREE"] ||
        false
    end

    def before_resolution
      Bundler.ui.info "Resolving dependencies...", debug?
    end

    def after_resolution
      Bundler.ui.info ""
    end

    def indicate_progress
      Bundler.ui.info ".", false unless debug?
    end

    include Molinillo::SpecificationProvider

    def dependencies_for(specification)
      specification.dependencies_for_activated_platforms
    end

    def search_for(dependency)
      @search_for[dependency] ||= begin
        name = dependency.name
        locked_results = @base[name].select {|spec| requirement_satisfied_by?(dependency, nil, spec) }
        locked_requirement = base_requirements[name]
        results = results_for(dependency) + locked_results
        results = results.select {|spec| requirement_satisfied_by?(locked_requirement, nil, spec) } if locked_requirement
        dep_platforms = dependency.gem_platforms(@platforms)

        @gem_version_promoter.sort_versions(dependency, results).group_by(&:version).reduce([]) do |groups, (_, specs)|
          relevant_platforms = dep_platforms.select {|platform| specs.any? {|spec| spec.match_platform(platform) } }
          next groups unless relevant_platforms.any?

          ruby_specs = select_best_platform_match(specs, Gem::Platform::RUBY)
          if ruby_specs.any?
            spec_group_ruby = SpecGroup.new(ruby_specs, [Gem::Platform::RUBY])
            spec_group_ruby.force_ruby_platform = dependency.force_ruby_platform
            groups << spec_group_ruby
          end

          next groups if @resolving_only_for_ruby || dependency.force_ruby_platform

          platform_specs = relevant_platforms.flat_map {|platform| select_best_platform_match(specs, platform) }
          next groups if platform_specs == ruby_specs

          spec_group = SpecGroup.new(platform_specs, relevant_platforms)
          groups << spec_group

          groups
        end
      end
    end

    def index_for(dependency)
      source_for(dependency.name).specs
    end

    def source_for(name)
      @source_requirements[name] || @source_requirements[:default]
    end

    def results_for(dependency)
      @results_for[dependency] ||= index_for(dependency).search(dependency)
    end

    def name_for(dependency)
      dependency.name
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue StandardError
      "Gemfile"
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      requirement.matches_spec?(spec) || spec.source.is_a?(Source::Gemspec)
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        vertex = activated.vertex_named(name)
        [
          @base[name].any? ? 0 : 1,
          vertex.payload ? 0 : 1,
          vertex.root? ? 0 : 1,
          amount_constrained(dependency),
          conflicts[name] ? 0 : 1,
          vertex.payload ? 0 : search_for(dependency).count,
        ]
      end
    end

    private

    def base_requirements
      @base.base_requirements
    end

    def prerelease_specified
      @gem_version_promoter.prerelease_specified
    end

    def remove_from_candidates(spec)
      @base.delete(spec)

      @results_for.keys.each do |dep|
        next unless dep.name == spec.name

        @results_for[dep].reject {|s| s.name == spec.name && s.version == spec.version }
      end

      reset_spec_cache
    end

    def reset_spec_cache
      @search_for = {}
      @gem_version_promoter.reset
    end

    # returns an integer \in (-\infty, 0]
    # a number closer to 0 means the dependency is less constraining
    #
    # dependencies w/ 0 or 1 possibilities (ignoring version requirements)
    # are given very negative values, so they _always_ sort first,
    # before dependencies that are unconstrained
    def amount_constrained(dependency)
      @amount_constrained ||= {}
      @amount_constrained[dependency.name] ||= if (base = @base[dependency.name]) && !base.empty?
        dependency.requirement.satisfied_by?(base.first.version) ? 0 : 1
      else
        all = index_for(dependency).search(dependency.name).size

        if all <= 1
          all - 1_000_000
        else
          search = search_for(dependency)
          search = prerelease_specified[dependency.name] ? search.count : search.count {|s| !s.version.prerelease? }
          search - all
        end
      end
    end

    def verify_gemfile_dependencies_are_found!(requirements)
      requirements.map! do |requirement|
        name = requirement.name
        next requirement if name == "bundler"
        next if requirement.gem_platforms(@platforms).empty?
        next requirement unless search_for(requirement).empty?
        next unless requirement.current_platform?

        raise GemNotFound, gem_not_found_message(name, requirement, source_for(name))
      end.compact!
    end

    def gem_not_found_message(name, requirement, source, extra_message = "")
      specs = source.specs.search(name).sort_by {|s| [s.version, s.platform.to_s] }
      matching_part = name
      requirement_label = SharedHelpers.pretty_dependency(requirement)
      cache_message = begin
                          " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                        rescue GemfileNotFound
                          nil
                        end
      specs_matching_requirement = specs.select {| spec| requirement.matches_spec?(spec) }

      if specs_matching_requirement.any?
        specs = specs_matching_requirement
        matching_part = requirement_label
        platforms = requirement.gem_platforms(@platforms)
        platform_label = platforms.size == 1 ? "platform '#{platforms.first}" : "platforms '#{platforms.join("', '")}"
        requirement_label = "#{requirement_label}' with #{platform_label}"
      end

      message = String.new("Could not find gem '#{requirement_label}'#{extra_message} in #{source}#{cache_message}.\n")

      if specs.any?
        message << "\nThe source contains the following gems matching '#{matching_part}':\n"
        message << specs.map {|s| "  * #{s.full_name}" }.join("\n")
      end

      message
    end

    def version_conflict_message(e)
      # only show essential conflicts, if possible
      conflicts = e.conflicts.dup

      if conflicts["bundler"]
        conflicts.replace("bundler" => conflicts["bundler"])
      else
        conflicts.delete_if do |_name, conflict|
          deps = conflict.requirement_trees.map(&:last).flatten(1)
          !Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
        end
      end

      e = Molinillo::VersionConflict.new(conflicts, e.specification_provider) unless conflicts.empty?

      e.message_with_trees(
        :full_message_for_conflict => lambda do |name, conflict|
          trees = conflict.requirement_trees

          # called first, because we want to reduce the amount of work required to find maximal empty sets
          trees = trees.uniq {|t| t.flatten.map {|dep| [dep.name, dep.requirement] } }

          # bail out if tree size is too big for Array#combination to make any sense
          if trees.size <= 15
            maximal = 1.upto(trees.size).map do |size|
              trees.map(&:last).flatten(1).combination(size).to_a
            end.flatten(1).select do |deps|
              Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
            end.min_by(&:size)

            trees.reject! {|t| !maximal.include?(t.last) } if maximal

            trees.sort_by! {|t| t.reverse.map(&:name) }
          end

          if trees.size > 1 || name == "bundler"
            o = if name.end_with?("\0")
              String.new("Bundler found conflicting requirements for the #{name} version:")
            else
              String.new("Bundler could not find compatible versions for gem \"#{name}\":")
            end
            o << %(\n)
            o << %(  In #{name_for_explicit_dependency_source}:\n)
            o << trees.map do |tree|
              t = "".dup
              depth = 2

              base_tree = tree.first
              base_tree_name = base_tree.name

              if base_tree_name.end_with?("\0")
                t = nil
              else
                tree.each do |req|
                  t << "  " * depth << SharedHelpers.pretty_dependency(req)
                  unless tree.last == req
                    if spec = conflict.activated_by_name[req.name]
                      t << %( was resolved to #{spec.version}, which)
                    end
                    t << %( depends on)
                  end
                  t << %(\n)
                  depth += 1
                end
              end
              t
            end.compact.join("\n")
          else
            o = String.new
          end

          if name == "bundler"
            o << %(\n  Current Bundler version:\n    bundler (#{Bundler::VERSION}))

            conflict_dependency = conflict.requirement
            conflict_requirement = conflict_dependency.requirement
            other_bundler_required = !conflict_requirement.satisfied_by?(Gem::Version.new(Bundler::VERSION))

            if other_bundler_required
              o << "\n\n"

              candidate_specs = source_for(:default_bundler).specs.search(conflict_dependency)
              if candidate_specs.any?
                target_version = candidate_specs.last.version
                new_command = [File.basename($PROGRAM_NAME), "_#{target_version}_", *ARGV].join(" ")
                o << "Your bundle requires a different version of Bundler than the one you're running.\n"
                o << "Install the necessary version with `gem install bundler:#{target_version}` and rerun bundler using `#{new_command}`\n"
              else
                o << "Your bundle requires a different version of Bundler than the one you're running, and that version could not be found.\n"
              end
            end
          elsif name.end_with?("\0")
            o << %(\n  Current #{name} version:\n    #{SharedHelpers.pretty_dependency(@metadata_requirements.find {|req| req.name == name })}\n\n)
          elsif !conflict.existing
            o << "\n"

            relevant_source = conflict.requirement.source || source_for(name)

            extra_message = if trees.first.size > 1
              ", which is required by gem '#{SharedHelpers.pretty_dependency(trees.first[-2])}',"
            else
              ""
            end

            o << gem_not_found_message(name, conflict.requirement, relevant_source, extra_message)
          end

          o
        end
      )
    end
  end
end
