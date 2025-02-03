# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits the `bottle` block in formulae.
      class BottleFormat < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          bottle_node = find_block(formula_nodes.body_node, :bottle)
          return if bottle_node.nil?

          sha256_nodes = find_method_calls_by_name(bottle_node.body, :sha256)
          cellar_node = find_node_method_by_name(bottle_node.body, :cellar)
          cellar_source = cellar_node&.first_argument&.source

          if sha256_nodes.present? && cellar_node.present?
            offending_node(cellar_node)
            problem "`cellar` should be a parameter to `sha256`" do |corrector|
              corrector.remove(range_by_whole_lines(cellar_node.source_range, include_final_newline: true))
            end
          end

          sha256_nodes.each do |sha256_node|
            sha256_hash = sha256_node.last_argument
            sha256_pairs = sha256_hash.pairs
            next if sha256_pairs.count != 1

            sha256_pair = sha256_pairs.first
            sha256_key = sha256_pair.key
            sha256_value = sha256_pair.value
            next unless sha256_value.sym_type?

            tag = sha256_value.value
            digest_source = sha256_key.source
            sha256_line = if cellar_source.present?
              "sha256 cellar: #{cellar_source}, #{tag}: #{digest_source}"
            else
              "sha256 #{tag}: #{digest_source}"
            end

            offending_node(sha256_node)
            problem "`sha256` should use new syntax" do |corrector|
              corrector.replace(sha256_node.source_range, sha256_line)
            end
          end
        end
      end

      # This cop audits the indentation of the bottle tags in the `bottle` block in formulae.
      class BottleTagIndentation < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          bottle_node = find_block(formula_nodes.body_node, :bottle)
          return if bottle_node.nil?

          sha256_nodes = find_method_calls_by_name(bottle_node.body, :sha256)

          max_tag_column = 0
          sha256_nodes.each do |sha256_node|
            sha256_hash = sha256_node.last_argument
            tag_column = T.let(sha256_hash.pairs.last.source_range.column, Integer)

            max_tag_column = tag_column if tag_column > max_tag_column
          end
          # This must be in a separate loop to make sure max_tag_column is truly the maximum
          sha256_nodes.each do |sha256_node| # rubocop:disable Style/CombinableLoops
            sha256_hash = sha256_node.last_argument
            hash = sha256_hash.pairs.last
            tag_column = hash.source_range.column

            next if tag_column == max_tag_column

            offending_node(hash)
            problem "Align bottle tags" do |corrector|
              new_line = (" " * (max_tag_column - tag_column)) + hash.source
              corrector.replace(hash.source_range, new_line)
            end
          end
        end
      end

      # This cop audits the indentation of the sha256 digests in the`bottle` block in formulae.
      class BottleDigestIndentation < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          bottle_node = find_block(formula_nodes.body_node, :bottle)
          return if bottle_node.nil?

          sha256_nodes = find_method_calls_by_name(bottle_node.body, :sha256)

          max_digest_column = 0
          sha256_nodes.each do |sha256_node|
            sha256_hash = sha256_node.last_argument
            digest_column = T.let(sha256_hash.pairs.last.value.source_range.column, Integer)

            max_digest_column = digest_column if digest_column > max_digest_column
          end
          # This must be in a separate loop to make sure max_digest_column is truly the maximum
          sha256_nodes.each do |sha256_node| # rubocop:disable Style/CombinableLoops
            sha256_hash = sha256_node.last_argument
            hash = sha256_hash.pairs.last.value
            digest_column = hash.source_range.column

            next if digest_column == max_digest_column

            offending_node(hash)
            problem "Align bottle digests" do |corrector|
              new_line = (" " * (max_digest_column - digest_column)) + hash.source
              corrector.replace(hash.source_range, new_line)
            end
          end
        end
      end

      # This cop audits the order of the `bottle` block in formulae.
      class BottleOrder < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          bottle_node = find_block(formula_nodes.body_node, :bottle)
          return if bottle_node.nil?
          return if bottle_node.child_nodes.blank?

          non_sha256_nodes = []
          sha256_nodes = []

          bottle_block_method_calls = if bottle_node.child_nodes.last.begin_type?
            bottle_node.child_nodes.last.child_nodes
          else
            [bottle_node.child_nodes.last]
          end

          bottle_block_method_calls.each do |node|
            if node.method_name == :sha256
              sha256_nodes << node
            else
              non_sha256_nodes << node
            end
          end

          arm64_nodes = []
          intel_nodes = []

          sha256_nodes.each do |node|
            version = sha256_bottle_tag node
            if version.to_s.start_with? "arm64"
              arm64_nodes << node
            else
              intel_nodes << node
            end
          end

          return if sha256_order(sha256_nodes) == sha256_order(arm64_nodes + intel_nodes)

          offending_node(bottle_node)
          problem "ARM bottles should be listed before Intel bottles" do |corrector|
            lines = ["bottle do"]
            lines += non_sha256_nodes.map { |node| "    #{node.source}" }
            lines += arm64_nodes.map { |node| "    #{node.source}" }
            lines += intel_nodes.map { |node| "    #{node.source}" }
            lines << "  end"
            corrector.replace(bottle_node.source_range, lines.join("\n"))
          end
        end

        sig { params(nodes: T::Array[RuboCop::AST::SendNode]).returns(T::Array[T.any(String, Symbol)]) }
        def sha256_order(nodes)
          nodes.map do |node|
            sha256_bottle_tag node
          end
        end

        sig { params(node: AST::SendNode).returns(T.any(String, Symbol)) }
        def sha256_bottle_tag(node)
          hash_pair = node.last_argument.pairs.last
          if hash_pair.key.sym_type?
            hash_pair.key.value
          else
            hash_pair.value.value
          end
        end
      end
    end
  end
end
