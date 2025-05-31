# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that deprecated checksums are not used.
      class Checksum < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node

          problem "MD5 checksums are deprecated, please use SHA-256" if method_called_ever?(body_node, :md5)

          problem "SHA1 checksums are deprecated, please use SHA-256" if method_called_ever?(body_node, :sha1)

          sha256_calls = find_every_method_call_by_name(body_node, :sha256)
          sha256_calls.each do |sha256_call|
            sha256_node = get_checksum_node(sha256_call)
            audit_sha256(sha256_node)
          end
        end

        sig { params(checksum: T.nilable(RuboCop::AST::Node)).void }
        def audit_sha256(checksum)
          return if checksum.nil?

          if regex_match_group(checksum, /^$/)
            problem "`sha256` is empty"
            return
          end

          if string_content(checksum).size != 64 && regex_match_group(checksum, /^\w*$/)
            problem "`sha256` should be 64 characters"
          end

          return unless regex_match_group(checksum, /[^a-f0-9]+/i)

          add_offense(T.must(@offensive_source_range), message: "`sha256` contains invalid characters")
        end
      end

      # This cop makes sure that checksum strings are lowercase.
      class ChecksumCase < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          sha256_calls = find_every_method_call_by_name(formula_nodes.body_node, :sha256)
          sha256_calls.each do |sha256_call|
            checksum = get_checksum_node(sha256_call)
            next if checksum.nil?
            next unless regex_match_group(checksum, /[A-F]+/)

            add_offense(@offensive_source_range, message: "`sha256` should be lowercase") do |corrector|
              correction = T.must(@offensive_node).source.downcase
              corrector.insert_before(T.must(@offensive_node).source_range, correction)
              corrector.remove(T.must(@offensive_node).source_range)
            end
          end
        end
      end
    end
  end
end
