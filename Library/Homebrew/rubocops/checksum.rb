# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that deprecated checksums are not used.
      class Checksum < FormulaCop
        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          problem "MD5 checksums are deprecated, please use SHA-256" if method_called_ever?(body_node, :md5)

          problem "SHA1 checksums are deprecated, please use SHA-256" if method_called_ever?(body_node, :sha1)

          sha256_calls = find_every_method_call_by_name(body_node, :sha256)
          sha256_calls.each do |sha256_call|
            sha256_node = get_checksum_node(sha256_call)
            audit_sha256(sha256_node)
          end
        end

        def audit_sha256(checksum)
          return if checksum.nil?

          if regex_match_group(checksum, /^$/)
            problem "sha256 is empty"
            return
          end

          if string_content(checksum).size != 64 && regex_match_group(checksum, /^\w*$/)
            problem "sha256 should be 64 characters"
          end

          return unless regex_match_group(checksum, /[^a-f0-9]+/i)

          add_offense(@offensive_source_range, message: "sha256 contains invalid characters")
        end
      end

      # This cop makes sure that checksum strings are lowercase.
      class ChecksumCase < FormulaCop
        extend AutoCorrector

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          sha256_calls = find_every_method_call_by_name(body_node, :sha256)
          sha256_calls.each do |sha256_call|
            checksum = get_checksum_node(sha256_call)
            next if checksum.nil?
            next unless regex_match_group(checksum, /[A-F]+/)

            add_offense(@offensive_source_range, message: "sha256 should be lowercase") do |corrector|
              correction = @offensive_node.source.downcase
              corrector.insert_before(@offensive_node.source_range, correction)
              corrector.remove(@offensive_node.source_range)
            end
          end
        end
      end
    end
  end
end
