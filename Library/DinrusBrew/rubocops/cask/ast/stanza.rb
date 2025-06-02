# typed: strict
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

        sig {
          params(
            method_node:  RuboCop::AST::Node,
            all_comments: T::Array[T.any(String, Parser::Source::Comment)],
          ).void
        }
        def initialize(method_node, all_comments)
          @method_node = T.let(method_node, RuboCop::AST::Node)
          @all_comments = T.let(all_comments, T::Array[T.any(String, Parser::Source::Comment)])
        end

        sig { returns(RuboCop::AST::Node) }
        attr_reader :method_node
        alias stanza_node method_node

        sig { returns(T::Array[T.any(Parser::Source::Comment, String)]) }
        attr_reader :all_comments

        def_delegator :stanza_node, :parent, :parent_node
        def_delegator :stanza_node, :arch_variable?
        def_delegator :stanza_node, :on_system_block?

        sig { returns(Parser::Source::Range) }
        def source_range
          stanza_node.location_expression
        end

        sig { returns(Parser::Source::Range) }
        def source_range_with_comments
          comments.reduce(source_range) do |range, comment|
            range.join(comment.loc.expression)
          end
        end

        def_delegator :source_range, :source
        def_delegator :source_range_with_comments, :source,
                      :source_with_comments

        sig { returns(Symbol) }
        def stanza_name
          return :on_arch_conditional if arch_variable?
          return stanza_node.method_node&.method_name if stanza_node.block_type?

          T.cast(stanza_node, RuboCop::AST::SendNode).method_name
        end

        sig { returns(T.nilable(T::Array[Symbol])) }
        def stanza_group
          Constants::STANZA_GROUP_HASH[stanza_name]
        end

        sig { returns(T.nilable(Integer)) }
        def stanza_index
          Constants::STANZA_ORDER.index(stanza_name)
        end

        sig { params(other: Stanza).returns(T::Boolean) }
        def same_group?(other)
          stanza_group == other.stanza_group
        end

        sig { returns(T::Array[Parser::Source::Comment]) }
        def comments
          @comments ||= T.let(
            stanza_node.each_node.reduce([]) do |comments, node|
              comments | comments_hash[node.loc]
            end,
            T.nilable(T::Array[Parser::Source::Comment]),
          )
        end

        sig { returns(T::Hash[Parser::Source::Range, T::Array[Parser::Source::Comment]]) }
        def comments_hash
          @comments_hash ||= T.let(
            Parser::Source::Comment.associate_locations(stanza_node.parent, all_comments),
            T.nilable(T::Hash[Parser::Source::Range, T::Array[Parser::Source::Comment]]),
          )
        end

        sig { params(other: T.untyped).returns(T::Boolean) }
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
