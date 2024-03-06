# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks if redundant components are present and for other component errors.
      #
      # - `url|checksum|mirror|version` should be inside `stable` block
      # - `head` and `head do` should not be simultaneously present
      # - `bottle :unneeded`/`:disable` and `bottle do` should not be simultaneously present
      # - `stable do` should not be present without a `head` spec
      # - `stable do` should not be present with only `url|checksum|mirror|version`
      # - `head do` should not be present with only `url`
      class ComponentsRedundancy < FormulaCop
        HEAD_MSG = "`head` and `head do` should not be simultaneously present"
        BOTTLE_MSG = "`bottle :modifier` and `bottle do` should not be simultaneously present"
        STABLE_MSG = "`stable do` should not be present without a `head` spec"
        STABLE_BLOCK_METHODS = [:url, :sha256, :mirror, :version].freeze

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          urls = find_method_calls_by_name(body_node, :url)

          urls.each do |url|
            url.arguments.each do |arg|
              next if arg.class != RuboCop::AST::HashNode

              url_args = arg.keys.each.map(&:value)
              if method_called?(body_node, :sha256) && url_args.include?(:tag) && url_args.include?(:revision)
                problem "Do not use both sha256 and tag/revision."
              end
            end
          end

          stable_block = find_block(body_node, :stable)
          if stable_block
            STABLE_BLOCK_METHODS.each do |method_name|
              problem "`#{method_name}` should be put inside `stable` block" if method_called?(body_node, method_name)
            end

            unless stable_block.body.nil?
              child_nodes = stable_block.body.begin_type? ? stable_block.body.child_nodes : [stable_block.body]
              if child_nodes.all? { |n| n.send_type? && STABLE_BLOCK_METHODS.include?(n.method_name) }
                problem "`stable do` should not be present with only #{STABLE_BLOCK_METHODS.join("/")}"
              end
            end
          end

          head_block = find_block(body_node, :head)
          if head_block && !head_block.body.nil?
            child_nodes = head_block.body.begin_type? ? head_block.body.child_nodes : [head_block.body]
            if child_nodes.all? { |n| n.send_type? && n.method_name == :url }
              problem "`head do` should not be present with only `url`"
            end
          end

          problem HEAD_MSG if method_called?(body_node, :head) &&
                              find_block(body_node, :head)

          problem BOTTLE_MSG if method_called?(body_node, :bottle) &&
                                find_block(body_node, :bottle)

          return if method_called?(body_node, :head) ||
                    find_block(body_node, :head)

          problem STABLE_MSG if stable_block
        end
      end
    end
  end
end
