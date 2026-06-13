# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Formula
      extend T::Helpers

      requires_ancestor { ::Formula }

      sig { returns(String) }
      def loader_path
        "$ORIGIN"
      end

      sig { params(spec: SoftwareSpec).void }
      def add_global_deps_to_spec(spec)
        @global_deps ||= T.let(nil, T.nilable(T::Array[Dependency]))
        @global_deps ||= begin
          dependency_collector = spec.dependency_collector
          related_formula_names = Set[name]
          if ::DevelopmentTools.needs_build_formulae? || ::DevelopmentTools.needs_libc_formula?
            related_formula_names.merge(aliases)
            related_formula_names.merge(versioned_formulae_names)
          end
          [
            dependency_collector.bubblewrap_dep_if_needed(related_formula_names),
            dependency_collector.gcc_dep_if_needed(related_formula_names),
            dependency_collector.glibc_dep_if_needed(related_formula_names),
          ].compact.freeze
        end
        @global_deps.each { |dep| spec.dependency_collector.add(dep) }
      end

      sig { returns(T::Boolean) }
      def valid_platform?
        supports_linux?
      end
    end
  end
end

Formula.prepend(OS::Linux::Formula)
