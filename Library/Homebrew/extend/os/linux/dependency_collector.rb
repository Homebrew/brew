# typed: strict
# frozen_string_literal: true

require "os/linux/glibc"
require "sandbox"

module OS
  module Linux
    module DependencyCollector
      sig { params(related_formula_names: T::Set[String]).returns(T.nilable(Dependency)) }
      def bubblewrap_dep_if_needed(related_formula_names)
        return unless bubblewrap_dependency_needed?
        return if building_global_dep_tree?
        return if related_formula_names.include?(BUBBLEWRAP)
        return if global_dep_tree[BUBBLEWRAP]&.intersect?(related_formula_names)
        return unless formula_for(BUBBLEWRAP)

        Dependency.new(BUBBLEWRAP, [:implicit])
      end

      sig { params(related_formula_names: T::Set[String]).returns(T.nilable(Dependency)) }
      def gcc_dep_if_needed(related_formula_names)
        # gcc is required for libgcc_s.so.1 if glibc or gcc are too old
        return unless ::DevelopmentTools.needs_build_formulae?
        return if building_global_dep_tree?
        return if related_formula_names.include?(GCC)
        return if global_dep_tree[GCC]&.intersect?(related_formula_names)
        return unless formula_for(GCC)

        Dependency.new(GCC, [:implicit])
      end

      sig { params(related_formula_names: T::Set[String]).returns(T.nilable(Dependency)) }
      def glibc_dep_if_needed(related_formula_names)
        return unless ::DevelopmentTools.needs_libc_formula?
        return if building_global_dep_tree?
        return if related_formula_names.include?(GLIBC)
        return if global_dep_tree[GLIBC]&.intersect?(related_formula_names)
        return unless formula_for(GLIBC)

        Dependency.new(GLIBC, [:implicit])
      end

      private

      GLIBC = "glibc"
      GCC = OS::LINUX_PREFERRED_GCC_RUNTIME_FORMULA
      BUBBLEWRAP = "bubblewrap"
      private_constant :GLIBC, :GCC, :BUBBLEWRAP

      sig { void }
      def init_global_dep_tree_if_needed!
        return if building_global_dep_tree?

        sandbox_tree_needed = bubblewrap_dependency_needed?
        build_formulae_tree_needed = ::DevelopmentTools.needs_build_formulae?
        return if !sandbox_tree_needed && !build_formulae_tree_needed
        return if (!sandbox_tree_needed || global_dep_tree.key?(BUBBLEWRAP)) &&
                  (!build_formulae_tree_needed || (global_dep_tree.key?(GLIBC) && global_dep_tree.key?(GCC)))

        building_global_dep_tree!
        if sandbox_tree_needed
          include_build = OS.not_tier_one_configuration? || build_formulae_tree_needed
          global_dep_tree[BUBBLEWRAP] = Set.new(global_deps_for(BUBBLEWRAP, include_build:))
        end
        if build_formulae_tree_needed
          global_dep_tree[GLIBC] = Set.new(global_deps_for(GLIBC))
          # gcc depends on glibc
          global_dep_tree[GCC] = Set.new([*global_deps_for(GCC), GLIBC, *@@global_dep_tree[GLIBC]])
          # bubblewrap depends on gcc
          global_dep_tree[BUBBLEWRAP]&.merge([GCC, *@@global_dep_tree[GCC]])
        end
        built_global_dep_tree!
      end

      sig { params(name: String).returns(T.nilable(::Formula)) }
      def formula_for(name)
        @formula_for ||= T.let({}, T.nilable(T::Hash[String, ::Formula]))
        @formula_for[name] ||= ::Formula[name]
      rescue FormulaUnavailableError
        nil
      end

      sig { returns(T::Boolean) }
      def bubblewrap_dependency_needed?
        return false unless ::Homebrew::EnvConfig.sandbox_linux?
        return false if ENV["HOMEBREW_TESTS"]

        ::Sandbox.executable.blank?
      end

      sig { params(name: String, include_build: T::Boolean).returns(T::Array[String]) }
      def global_deps_for(name, include_build: true)
        @global_deps_for ||= T.let({}, T.nilable(T::Hash[String, T::Array[String]]))
        # Always strip out glibc and gcc from all parts of dependency tree when
        # we're calculating their dependency trees. Other parts of Homebrew will
        # catch any circular dependencies.
        @global_deps_for["#{name}|#{include_build}"] ||= if (formula = formula_for(name))
          formula.deps.filter_map do |dep|
            next if dep.test? && !dep.build?
            next if dep.build? && !include_build

            [dep.name, *global_deps_for(dep.name, include_build:)].compact
          end.flatten.uniq
        else
          []
        end
      end

      # Use class variables to avoid this expensive logic needing to be done more
      # than once.
      # rubocop:disable Style/ClassVars
      @@global_dep_tree = T.let({}, T::Hash[String, T::Set[String]])
      @@building_global_dep_tree = T.let(false, T::Boolean)

      sig { returns(T::Hash[String, T::Set[String]]) }
      def global_dep_tree
        @@global_dep_tree
      end

      sig { void }
      def building_global_dep_tree!
        @@building_global_dep_tree = true
      end

      sig { void }
      def built_global_dep_tree!
        @@building_global_dep_tree = false
      end

      sig { returns(T::Boolean) }
      def building_global_dep_tree?
        @@building_global_dep_tree.present?
      end
      # rubocop:enable Style/ClassVars
    end
  end
end

DependencyCollector.prepend(OS::Linux::DependencyCollector)
