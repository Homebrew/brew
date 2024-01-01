# typed: true
# frozen_string_literal: true

require "tsort"

module Utils
  # Topologically sortable hash map.
  class TopologicalHash < Hash
    include TSort

    sig {
      params(
        packages:    T.any(Cask::Cask, Formula, T::Array[T.any(Cask::Cask, Formula)]),
        accumulator: TopologicalHash,
      ).returns(TopologicalHash)
    }
    def self.graph_package_dependencies(packages, accumulator = TopologicalHash.new)
      packages = Array(packages)

      packages.each do |cask_or_formula|
        next if accumulator.key?(cask_or_formula)

        if cask_or_formula.is_a?(Cask::Cask)
          formula_deps = cask_or_formula.depends_on
                                        .formula
                                        .map { |f| Formula[f] }
          cask_deps = cask_or_formula.depends_on
                                     .cask
                                     .map { |c| Cask::CaskLoader.load(c, config: nil) }
        else
          formula_deps = cask_or_formula.deps
                                        .reject(&:build?)
                                        .reject(&:test?)
                                        .map(&:to_formula)
          cask_deps = cask_or_formula.requirements
                                     .map(&:cask)
                                     .compact
                                     .map { |c| Cask::CaskLoader.load(c, config: nil) }
        end

        accumulator[cask_or_formula] = formula_deps + cask_deps

        graph_package_dependencies(formula_deps, accumulator)
        graph_package_dependencies(cask_deps, accumulator)
      end

      accumulator
    end

    private

    def tsort_each_node(&block)
      each_key(&block)
    end

    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end
end
