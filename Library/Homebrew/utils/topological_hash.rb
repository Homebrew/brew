# typed: strict
# frozen_string_literal: true

require "tsort"

module Utils
  # Topologically sortable hash map.
  class TopologicalHash < Hash
    extend T::Generic
    include TSort

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
                                        .reject(&:build?)
                                        .reject(&:test?)
                                        .map(&:to_formula)
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

    sig { params(block: T.proc.params(arg0: K).void).void }
    def tsort_each_node(&block)
      each_key(&block)
    end

    sig { params(node: K, block: T.proc.params(arg0: CaskOrFormula).void).returns(V) }
    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end
end
