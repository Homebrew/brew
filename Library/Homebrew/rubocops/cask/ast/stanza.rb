# typed: true
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cask
    module AST
      # This class wraps the AST send/block node that encapsulates the method
      # call that comprises the stanza. It includes various helper methods to
      # aid cops in their analysis.
      class Stanza
        extend Forwardable

        def initialize(method_node, all_comments)
          @method_node = method_node
          @all_comments = all_comments
        end

        attr_reader :method_node, :all_comments

        alias stanza_node method_node

        def_delegator :stanza_node, :parent, :parent_node
        def_delegator :stanza_node, :arch_variable?
        def_delegator :stanza_node, :on_system_block?

        def source_range
          stanza_node.location_expression
        end

        def source_range_with_comments
          comments.reduce(source_range) do |range, comment|
            range.join(comment.loc.expression)
          end
        end

        def_delegator :source_range, :source
        def_delegator :source_range_with_comments, :source,
                      :source_with_comments

        def stanza_name
          return :on_arch_conditional if arch_variable?

          stanza_node.method_name
        end

        def stanza_group
          Constants::STANZA_GROUP_HASH[stanza_name]
        end

        def stanza_index
          Constants::STANZA_ORDER.index(stanza_name)
        end

        def same_group?(other)
          stanza_group == other.stanza_group
        end

        def comments
          @comments ||= stanza_node.each_node.reduce([]) do |comments, node|
            comments | comments_hash[node.loc]
          end
        end

        def comments_hash
          @comments_hash ||= Parser::Source::Comment.associate_locations(stanza_node.parent, all_comments)
        end

        def ==(other)
          self.class == other.class && stanza_node == other.stanza_node
        end
        alias eql? ==

        Constants::STANZA_ORDER.each do |stanza_name|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{stanza_name.to_s.chomp("!")}?               # def url?
              stanza_name == :#{stanza_name}                  #   stanza_name == :url
            end                                               # end
          RUBY
        end
      end
    end
  end
end
