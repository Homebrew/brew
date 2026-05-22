# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "json"
require "keg"
require "tab"
require "utils/formatter"

module Homebrew
  module Cmd
    class Footprint < AbstractCommand
      cmd_args do
        description <<~EOS
          Show the true disk cost of installed formulae, including exclusive
          dependencies that would be freed on uninstall.

          When given formula arguments, show the footprint of each.
          With `--installed`, show all top-level (explicitly requested) formulae
          ranked by total footprint.
        EOS

        switch "--installed",
               description: "Show all installed formulae ranked by total disk footprint."
        switch "--all",
               depends_on:  "--installed",
               description: "Include formulae installed as dependencies, not just those installed on request."
        switch "--json",
               description: "Print a JSON representation of the footprint data."

        named_args :installed_formula
      end

      sig { override.void }
      def run
        if args.installed?
          run_installed
        elsif args.no_named?
          raise UsageError, "must specify formulae or use `--installed`."
        else
          run_named
        end
      end

      private

      sig { returns(T::Hash[String, T::Set[String]]) }
      def build_reverse_dep_map
        reverse_map = T.let(Hash.new { |h, k| h[k] = Set.new }, T::Hash[String, T::Set[String]])

        Formula.installed.each do |formula|
          keg = formula.any_installed_keg
          next unless keg

          deps = keg.runtime_dependencies
          next unless deps.is_a?(Array)

          deps.each do |dep|
            next unless dep.is_a?(Hash)

            full_name = dep["full_name"]
            next unless full_name

            dep_name = Utils.name_from_full_name(full_name)
            reverse_map[dep_name].add(formula.name)
          end
        end

        reverse_map
      end

      sig {
        params(
          formula:     Formula,
          reverse_map: T::Hash[String, T::Set[String]],
        ).returns(T::Hash[Symbol, T.untyped])
      }
      def analyze_formula(formula, reverse_map)
        kegs = formula.installed_kegs
        raise FormulaUnavailableError, formula.name if kegs.empty?

        direct_size = kegs.sum(&:disk_usage)

        keg = formula.any_installed_keg
        tab_deps = keg&.runtime_dependencies
        exclusive_deps = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
        shared_deps = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

        if tab_deps.is_a?(Array)
          tab_deps.each do |dep|
            next unless dep.is_a?(Hash)

            full_name = dep["full_name"]
            next unless full_name

            dep_name = Utils.name_from_full_name(full_name)
            dep_formula = begin
              Formula[dep_name]
            rescue FormulaUnavailableError
              next
            end

            dep_kegs = dep_formula.installed_kegs
            next if dep_kegs.empty?

            dep_size = dep_kegs.sum(&:disk_usage)
            dependents = reverse_map[dep_name]

            if dependents.size == 1 && dependents.include?(formula.name)
              exclusive_deps << { name: dep_name, size: dep_size }
            else
              also_needed_by = (dependents - [formula.name]).sort
              shared_deps << { name: dep_name, size: dep_size, also_needed_by: also_needed_by }
            end
          end
        end

        exclusive_deps_size = exclusive_deps.sum { |d| d[:size] }
        shared_deps_size = shared_deps.sum { |d| d[:size] }
        total_footprint = direct_size + exclusive_deps_size

        {
          name:                formula.name,
          version:             formula.any_installed_version.to_s,
          direct_size:         direct_size,
          exclusive_deps:      exclusive_deps,
          shared_deps:         shared_deps,
          exclusive_deps_size: exclusive_deps_size,
          shared_deps_size:    shared_deps_size,
          total_footprint:     total_footprint,
        }
      end

      sig { void }
      def run_installed
        reverse_map = build_reverse_dep_map
        installed = Formula.installed

        unless args.all?
          installed = installed.select do |f|
            f.any_installed_keg&.tab&.installed_on_request == true
          end
        end

        analyses = installed.filter_map do |formula|
          analyze_formula(formula, reverse_map)
        rescue FormulaUnavailableError
          nil
        end

        analyses.sort_by! { |a| -a[:total_footprint] }

        if args.json?
          output_json(analyses)
        else
          output_table(analyses)
        end
      end

      sig { void }
      def run_named
        reverse_map = build_reverse_dep_map
        formulae = args.named.to_formulae

        analyses = formulae.map do |formula|
          raise FormulaUnavailableError, formula.name unless formula.any_installed_keg

          analyze_formula(formula, reverse_map)
        end

        if args.json?
          output_json(analyses)
        else
          analyses.each_with_index do |analysis, i|
            puts if i.positive?
            output_single(analysis)
          end
        end
      end

      sig { params(analysis: T::Hash[Symbol, T.untyped]).void }
      def output_single(analysis)
        name = analysis[:name]
        direct = Formatter.disk_usage_readable(analysis[:direct_size])
        exclusive = analysis[:exclusive_deps]
        shared = analysis[:shared_deps]
        total = Formatter.disk_usage_readable(analysis[:total_footprint])

        if exclusive.empty? && shared.empty?
          puts "#{name}: #{direct}"
          return
        end

        if exclusive.empty?
          puts "#{name}: #{direct} (direct), no exclusive deps"
        else
          dep_count = exclusive.size
          excl_size = Formatter.disk_usage_readable(analysis[:exclusive_deps_size])
          puts "#{name}: #{direct} (direct) + #{excl_size} " \
               "(#{dep_count} exclusive #{Utils.pluralize("dep", dep_count)}) = #{total} total"
        end

        if shared.any?
          shared_size = Formatter.disk_usage_readable(analysis[:shared_deps_size])
          puts "  #{shared_size} in shared deps (would not be freed)"
        end

        return unless args.verbose?

        puts ""
        version = analysis[:version]
        puts "#{name} (#{version}): #{direct} direct"

        if exclusive.any?
          puts ""
          puts "Exclusive dependencies (only needed by #{name}):"
          exclusive.sort_by { |d| -d[:size] }.each do |dep|
            puts "  #{dep[:name].ljust(16)} #{Formatter.disk_usage_readable(dep[:size])}"
          end
        end

        if shared.any?
          puts ""
          puts "Shared dependencies (also needed by other formulae):"
          shared.sort_by { |d| -d[:size] }.each do |dep|
            also = dep[:also_needed_by]
            also_str = also.empty? ? "" : "  (also: #{also.join(", ")})"
            puts "  #{dep[:name].ljust(16)} #{Formatter.disk_usage_readable(dep[:size])}#{also_str}"
          end
        end

        puts ""
        puts "Total footprint: #{total} (direct + exclusive deps)"
      end

      sig { params(analyses: T::Array[T::Hash[Symbol, T.untyped]]).void }
      def output_table(analyses)
        return if analyses.empty?

        fmt = "%-20<pkg>s  %10<direct>s  %14<excl>s  %16<total>s"

        puts format(fmt, pkg: "Package", direct: "Direct", excl: "Excl. Deps", total: "Total Footprint")

        analyses.each do |analysis|
          puts format(
            fmt,
            pkg:    analysis[:name],
            direct: Formatter.disk_usage_readable(analysis[:direct_size]),
            excl:   Formatter.disk_usage_readable(analysis[:exclusive_deps_size]),
            total:  Formatter.disk_usage_readable(analysis[:total_footprint]),
          )
        end

        grand_total = analyses.sum { |a| a[:total_footprint] }
        puts format(fmt, pkg: "Total", direct: "", excl: "", total: Formatter.disk_usage_readable(grand_total))
      end

      sig { params(analyses: T::Array[T::Hash[Symbol, T.untyped]]).void }
      def output_json(analyses)
        data = {
          formulae: analyses.map do |a|
            {
              name:                a[:name],
              version:             a[:version],
              direct_size:         a[:direct_size],
              exclusive_deps:      a[:exclusive_deps].map { |d| { name: d[:name], size: d[:size] } },
              shared_deps:         a[:shared_deps].map do |d|
                { name: d[:name], size: d[:size], also_needed_by: d[:also_needed_by] }
              end,
              exclusive_deps_size: a[:exclusive_deps_size],
              shared_deps_size:    a[:shared_deps_size],
              total_footprint:     a[:total_footprint],
            }
          end,
        }
        puts JSON.pretty_generate(data)
      end
    end
  end
end
