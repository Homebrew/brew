# typed: strict
# frozen_string_literal: true

require "tsort"

module Utils
  # Cycle-tolerant ordering for graphs that include TSort.
  module CycleTolerantTSort
    extend T::Helpers

    requires_ancestor { TSort }

    # Orders nodes dependency-first like tsort but, unlike tsort, does not
    # raise on a cycle: yields cyclic components (size > 1) to the block and
    # returns the flattened component order.
    sig {
      params(on_cycle: T.proc.params(arg0: T::Array[T::Array[T.untyped]]).void)
        .returns(T::Array[T.untyped])
    }
    def tsort_with_cycles(&on_cycle)
      components = each_strongly_connected_component.to_a
      cycles = components.select { |component| component.size > 1 }
      yield(cycles) if cycles.any?
      components.flatten
    end
  end

  # Topologically sortable hash map.
  class TopologicalHash < Hash
    extend T::Generic
    include TSort
    include CycleTolerantTSort

    CaskOrFormula = T.type_alias { T.any(Cask::Cask, Formula) }

    K = type_member { { fixed: CaskOrFormula } }
    V = type_member { { fixed: T::Array[CaskOrFormula] } }
    Elem = type_member(:out) { { fixed: [CaskOrFormula, T::Array[CaskOrFormula]] } }

    sig {
      params(
        packages:    T.any(CaskOrFormula, T::Array[CaskOrFormula]),
        accumulator: TopologicalHash,
      ).returns(TopologicalHash)
    }
    def self.graph_package_dependencies(packages, accumulator = TopologicalHash.new)
      packages = Array(packages)

      packages.each do |cask_or_formula|
        next if accumulator.key?(cask_or_formula)

        case cask_or_formula
        when Cask::Cask
          formula_deps = cask_or_formula.depends_on
                                        .formula
                                        .map { |f| Formula[f] }
          cask_deps = cask_or_formula.depends_on
                                     .cask
                                     .map { |c| Cask::CaskLoader.load(c, config: nil) }
        when Formula
          formula_deps = cask_or_formula.deps
                                        .filter_map { |d| d.to_formula if !d.build? && !d.test? }
          cask_deps = cask_or_formula.requirements
                                     .filter_map(&:cask)
                                     .map { |c| Cask::CaskLoader.load(c, config: nil) }
        else
          T.absurd(cask_or_formula)
        end

        accumulator[cask_or_formula] = formula_deps + cask_deps

        graph_package_dependencies(formula_deps, accumulator)
        graph_package_dependencies(cask_deps, accumulator)
      end

      accumulator
    end

    private

    sig { override.params(block: T.proc.params(arg0: K).void).void }
    def tsort_each_node(&block)
      each_key(&block)
    end

    sig { override.params(node: K, block: T.proc.params(arg0: CaskOrFormula).void).returns(V) }
    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end
end
