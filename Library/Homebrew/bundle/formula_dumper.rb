# typed: true
# frozen_string_literal: true

require "json"
require "tsort"
require "utils/output"

module Homebrew
  module Bundle
    # TODO: refactor into multiple modules
    module FormulaDumper
      extend Utils::Output::Mixin

      def self.reset!
        require "bundle/brew_services"

        Homebrew::Bundle::BrewServices.reset!
        @formulae = nil
        @formulae_by_full_name = nil
        @formulae_by_name = nil
        @formula_aliases = nil
        @formula_oldnames = nil
      end

      def self.formulae
        return @formulae if @formulae

        formulae_by_full_name
        @formulae
      end

      def self.formulae_by_full_name(name = nil)
        return @formulae_by_full_name[name] if name.present? && @formulae_by_full_name&.key?(name)

        require "formula"
        require "formulary"
        Formulary.enable_factory_cache!

        @formulae_by_name ||= {}
        @formulae_by_full_name ||= {}

        if name.nil?
          formulae = Formula.installed.map { add_formula(it) }
          sort!(formulae)
          return @formulae_by_full_name
        end

        formula = Formula[name]
        add_formula(formula)
      rescue FormulaUnavailableError => e
        opoo "'#{name}' formula is unreadable: #{e}"
        {}
      end

      def self.formulae_by_name(name)
        formulae_by_full_name(name) || @formulae_by_name[name]
      end

      def self.dump(describe: false, no_restart: false)
        require "bundle/brew_services"

        requested_formula = formulae.select do |f|
          f[:installed_on_request?] || !f[:installed_as_dependency?]
        end
        requested_formula.map do |f|
          brewline = if describe && f[:desc].present?
            f[:desc].split("\n").map { |s| "# #{s}\n" }.join
          else
            ""
          end
          brewline += "brew \"#{f[:full_name]}\""

          args = f[:args].map { |arg| "\"#{arg}\"" }.sort.join(", ")
          brewline += ", args: [#{args}]" unless f[:args].empty?
          brewline += ", restart_service: :changed" if !no_restart && BrewServices.started?(f[:full_name])
          brewline += ", link: #{f[:link?]}" unless f[:link?].nil?
          brewline
        end.join("\n")
      end

      def self.formula_aliases
        return @formula_aliases if @formula_aliases

        @formula_aliases = {}
        formulae.each do |f|
          aliases = f[:aliases]
          next if aliases.blank?

          aliases.each do |a|
            @formula_aliases[a] = f[:full_name]
            if f[:full_name].include? "/" # tap formula
              tap_name = f[:full_name].rpartition("/").first
              @formula_aliases["#{tap_name}/#{a}"] = f[:full_name]
            end
          end
        end
        @formula_aliases
      end

      def self.formula_oldnames
        return @formula_oldnames if @formula_oldnames

        @formula_oldnames = {}
        formulae.each do |f|
          oldnames = f[:oldnames]
          next if oldnames.blank?

          oldnames.each do |oldname|
            @formula_oldnames[oldname] = f[:full_name]
            if f[:full_name].include? "/" # tap formula
              tap_name = f[:full_name].rpartition("/").first
              @formula_oldnames["#{tap_name}/#{oldname}"] = f[:full_name]
            end
          end
        end
        @formula_oldnames
      end

      private_class_method def self.add_formula(formula)
        hash = formula_to_hash formula

        @formulae_by_name[hash[:name]] = hash
        @formulae_by_full_name[hash[:full_name]] = hash

        hash
      end

      private_class_method def self.formula_to_hash(formula)
        keg = if formula.linked?
          link = true if formula.keg_only?
          formula.linked_keg
        else
          link = false unless formula.keg_only?
          formula.any_installed_prefix
        end

        if keg
          require "tab"

          tab = Tab.for_keg(keg)
          args = tab.used_options.map(&:name)
          version = begin
            keg.realpath.basename
          rescue
            # silently handle broken symlinks
            nil
          end.to_s
          args << "HEAD" if version.start_with?("HEAD")
          installed_as_dependency = tab.installed_as_dependency
          installed_on_request = tab.installed_on_request
          runtime_dependencies = if (runtime_deps = tab.runtime_dependencies)
            runtime_deps.filter_map { |d| d["full_name"] }

          end
          poured_from_bottle = tab.poured_from_bottle
        end

        runtime_dependencies ||= formula.runtime_dependencies.map(&:name)

        bottled = if (stable = formula.stable) && stable.bottle_defined?
          bottle_hash = formula.bottle_hash.deep_symbolize_keys
          stable.bottled?
        end

        {
          name:                     formula.name,
          desc:                     formula.desc,
          oldnames:                 formula.oldnames,
          full_name:                formula.full_name,
          aliases:                  formula.aliases,
          any_version_installed?:   formula.any_version_installed?,
          args:                     Array(args).uniq,
          version:,
          installed_as_dependency?: installed_as_dependency || false,
          installed_on_request?:    installed_on_request || false,
          dependencies:             runtime_dependencies,
          build_dependencies:       formula.deps.select(&:build?).map(&:name).uniq,
          conflicts_with:           formula.conflicts.map(&:name),
          pinned?:                  formula.pinned? || false,
          outdated?:                formula.outdated? || false,
          link?:                    link,
          poured_from_bottle?:      poured_from_bottle || false,
          bottle:                   bottle_hash || false,
          bottled:                  bottled || false,
          official_tap:             formula.tap&.official? || false,
        }
      end

      class Topo < Hash
        include TSort

        def each_key(&block)
          keys.each(&block)
        end
        alias tsort_each_node each_key

        def tsort_each_child(node, &block)
          fetch(node.downcase).sort.each(&block)
        end
      end

      private_class_method def self.sort!(formulae)
        # Step 1: Sort by formula full name while putting tap formulae behind core formulae.
        #         So we can have a nicer output.
        formulae = formulae.sort do |a, b|
          if a[:full_name].exclude?("/") && b[:full_name].include?("/")
            -1
          elsif a[:full_name].include?("/") && b[:full_name].exclude?("/")
            1
          else
            a[:full_name] <=> b[:full_name]
          end
        end

        # Step 2: Sort by formula dependency topology.
        topo = Topo.new
        formulae.each do |f|
          topo[f[:name]] = topo[f[:full_name]] = f[:dependencies].filter_map do |dep|
            ff = formulae_by_name(dep)
            next if ff.blank?
            next unless ff[:any_version_installed?]

            ff[:full_name]
          end
        end
        @formulae = topo.tsort
                        .map { |name| @formulae_by_full_name[name] || @formulae_by_name[name] }
                        .uniq { |f| f[:full_name] }
      rescue TSort::Cyclic => e
        e.message =~ /\["([^"]*)".*"([^"]*)"\]/
        cycle_first = Regexp.last_match(1)
        cycle_last = Regexp.last_match(2)
        odie e.message if !cycle_first || !cycle_last

        odie <<~EOS
          Formulae dependency graph sorting failed (likely due to a circular dependency):
          #{cycle_first}: #{topo[cycle_first] if topo}
          #{cycle_last}: #{topo[cycle_last] if topo}
          Please run the following commands and try again:
            brew update
            brew uninstall --ignore-dependencies --force #{cycle_first} #{cycle_last}
            brew install #{cycle_first} #{cycle_last}
        EOS
      end
    end
  end
end
