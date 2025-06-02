# frozen_string_literal: true

module Bundler
  class CLI::Outdated
    attr_reader :options, :gems, :options_include_groups, :filter_options_patch, :sources, :strict
    attr_accessor :outdated_gems

    def initialize(options, gems)
      @options = options
      @gems = gems
      @sources = Array(options[:source])

      @filter_options_patch = options.keys & %w[filter-major filter-minor filter-patch]

      @outdated_gems = []

      @options_include_groups = [:group, :groups].any? do |v|
        options.keys.include?(v.to_s)
      end

      # the patch level options imply strict is also true. It wouldn't make
      # sense otherwise.
      @strict = options["filter-strict"] || Bundler::CLI::Common.patch_level_options(options).any?
    end

    def run
      check_for_deployment_mode!

      gems.each do |gem_name|
        Bundler::CLI::Common.select_spec(gem_name)
      end

      Bundler.definition.validate_runtime!
      current_specs = Bundler.ui.silence { Bundler.definition.resolve }

      current_dependencies = Bundler.ui.silence do
        Bundler.load.dependencies.map {|dep| [dep.name, dep] }.to_h
      end

      definition = if gems.empty? && sources.empty?
        # We're doing a full update
        Bundler.definition(true)
      else
        Bundler.definition(:gems => gems, :sources => sources)
      end

      Bundler::CLI::Common.configure_gem_version_promoter(
        Bundler.definition,
        options.merge(:strict => @strict)
      )

      definition_resolution = proc do
        options[:local] ? definition.resolve_with_cache! : definition.resolve_remotely!
      end

      if options[:parseable]
        Bundler.ui.silence(&definition_resolution)
      else
        definition_resolution.call
      end

      Bundler.ui.info ""

      # Loop through the current specs
      gemfile_specs, dependency_specs = current_specs.partition do |spec|
        current_dependencies.key? spec.name
      end

      specs = if options["only-explicit"]
        gemfile_specs
      else
        gemfile_specs + dependency_specs
      end

      specs.sort_by(&:name).uniq(&:name).each do |current_spec|
        next unless gems.empty? || gems.include?(current_spec.name)

        active_spec = retrieve_active_spec(definition, current_spec)
        next unless active_spec

        next unless filter_options_patch.empty? || update_present_via_semver_portions(current_spec, active_spec, options)

        gem_outdated = Gem::Version.new(active_spec.version) > Gem::Version.new(current_spec.version)
        next unless gem_outdated || (current_spec.git_version != active_spec.git_version)

        dependency = current_dependencies[current_spec.name]
        groups = ""
        if dependency && !options[:parseable]
          groups = dependency.groups.join(", ")
        end

        outdated_gems << {
          :active_spec => active_spec,
          :current_spec => current_spec,
          :dependency => dependency,
          :groups => groups,
        }
      end

      if outdated_gems.empty?
        unless options[:parseable]
          Bundler.ui.info(nothing_outdated_message)
        end
      else
        if options_include_groups
          relevant_outdated_gems = outdated_gems.group_by {|g| g[:groups] }.sort.flat_map do |groups, gems|
            contains_group = groups.split(", ").include?(options[:group])
            next unless options[:groups] || contains_group

            gems
          end.compact

          if options[:parseable]
            relevant_outdated_gems.each do |gems|
              print_gems(gems)
            end
          else
            print_gems_table(relevant_outdated_gems)
          end
        elsif options[:parseable]
          print_gems(outdated_gems)
        else
          print_gems_table(outdated_gems)
        end

        exit 1
      end
    end

    private

    def loaded_from_for(spec)
      return unless spec.respond_to?(:loaded_from)

      spec.loaded_from
    end

    def groups_text(group_text, groups)
      "#{group_text}#{groups.split(",").size > 1 ? "s" : ""} \"#{groups}\""
    end

    def nothing_outdated_message
      if filter_options_patch.any?
        display = filter_options_patch.map do |o|
          o.sub("filter-", "")
        end.join(" or ")

        "No #{display} updates to display.\n"
      else
        "Bundle up to date!\n"
      end
    end

    def retrieve_active_spec(definition, current_spec)
      active_spec = definition.resolve.find_by_name_and_platform(current_spec.name, current_spec.platform)
      return unless active_spec

      return active_spec if strict

      active_specs = active_spec.source.specs.search(current_spec.name).select {|spec| spec.match_platform(current_spec.platform) }.sort_by(&:version)
      if !current_spec.version.prerelease? && !options[:pre] && active_specs.size > 1
        active_specs.delete_if {|b| b.respond_to?(:version) && b.version.prerelease? }
      end
      active_specs.last
    end

    def print_gems(gems_list)
      gems_list.each do |gem|
        print_gem(
          gem[:current_spec],
          gem[:active_spec],
          gem[:dependency],
          gem[:groups],
        )
      end
    end

    def print_gems_table(gems_list)
      data = gems_list.map do |gem|
        gem_column_for(
          gem[:current_spec],
          gem[:active_spec],
          gem[:dependency],
          gem[:groups],
        )
      end

      print_indented([table_header] + data)
    end

    def print_gem(current_spec, active_spec, dependency, groups)
      spec_version = "#{active_spec.version}#{active_spec.git_version}"
      if Bundler.ui.debug?
        loaded_from = loaded_from_for(active_spec)
        spec_version += " (from #{loaded_from})" if loaded_from
      end
      current_version = "#{current_spec.version}#{current_spec.git_version}"

      if dependency && dependency.specific?
        dependency_version = %(, requested #{dependency.requirement})
      end

      spec_outdated_info = "#{active_spec.name} (newest #{spec_version}, " \
        "installed #{current_version}#{dependency_version})"

      output_message = if options[:parseable]
        spec_outdated_info.to_s
      elsif options_include_groups || groups.empty?
        "  * #{spec_outdated_info}"
      else
        "  * #{spec_outdated_info} in #{groups_text("group", groups)}"
      end

      Bundler.ui.info output_message.rstrip
    end

    def gem_column_for(current_spec, active_spec, dependency, groups)
      current_version = "#{current_spec.version}#{current_spec.git_version}"
      spec_version = "#{active_spec.version}#{active_spec.git_version}"
      dependency = dependency.requirement if dependency

      ret_val = [active_spec.name, current_version, spec_version, dependency.to_s, groups.to_s]
      ret_val << loaded_from_for(active_spec).to_s if Bundler.ui.debug?
      ret_val
    end

    def check_for_deployment_mode!
      return unless Bundler.frozen_bundle?
      suggested_command = if Bundler.settings.locations("frozen").keys.&([:global, :local]).any?
        "bundle config unset frozen"
      elsif Bundler.settings.locations("deployment").keys.&([:global, :local]).any?
        "bundle config unset deployment"
      end
      raise ProductionError, "You are trying to check outdated gems in " \
        "deployment mode. Run `bundle outdated` elsewhere.\n" \
        "\nIf this is a development machine, remove the " \
        "#{Bundler.default_gemfile} freeze" \
        "\nby running `#{suggested_command}`."
    end

    def update_present_via_semver_portions(current_spec, active_spec, options)
      current_major = current_spec.version.segments.first
      active_major = active_spec.version.segments.first

      update_present = false
      update_present = active_major > current_major if options["filter-major"]

      if !update_present && (options["filter-minor"] || options["filter-patch"]) && current_major == active_major
        current_minor = get_version_semver_portion_value(current_spec, 1)
        active_minor = get_version_semver_portion_value(active_spec, 1)

        update_present = active_minor > current_minor if options["filter-minor"]

        if !update_present && options["filter-patch"] && current_minor == active_minor
          current_patch = get_version_semver_portion_value(current_spec, 2)
          active_patch = get_version_semver_portion_value(active_spec, 2)

          update_present = active_patch > current_patch
        end
      end

      update_present
    end

    def get_version_semver_portion_value(spec, version_portion_index)
      version_section = spec.version.segments[version_portion_index, 1]
      version_section.to_a[0].to_i
    end

    def print_indented(matrix)
      header = matrix[0]
      data = matrix[1..-1]

      column_sizes = Array.new(header.size) do |index|
        matrix.max_by {|row| row[index].length }[index].length
      end

      Bundler.ui.info justify(header, column_sizes)

      data.sort_by! {|row| row[0] }

      data.each do |row|
        Bundler.ui.info justify(row, column_sizes)
      end
    end

    def table_header
      header = ["Gem", "Current", "Latest", "Requested", "Groups"]
      header << "Path" if Bundler.ui.debug?
      header
    end

    def justify(row, sizes)
      row.each_with_index.map do |element, index|
        element.ljust(sizes[index])
      end.join("  ").strip + "\n"
    end
  end
end
