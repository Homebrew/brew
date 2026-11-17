# typed: strict
# frozen_string_literal: true

class RuboCop::Cop::VariableForce::Variable
  sig { returns(RuboCop::AST::Node) }
  def declaration_node; end
end

class RuboCop::Cop::VariableForce::VariableTable < Object; end

module RuboCop::Cop::ProjectIndexHelp
  sig { params(const_node: RuboCop::AST::ConstNode).returns(T.nilable(Rubydex::Declaration)) }
  def resolve_constant_in_index(const_node); end
end

class RuboCop::Cop::Metrics::Utils::CodeLengthCalculator
  sig {
    params(
      node:             RuboCop::AST::Node,
      processed_source: RuboCop::AST::ProcessedSource,
      count_comments:   T::Boolean,
      foldable_types:   T::Array[Symbol],
    ).void
  }
  def initialize(node, processed_source, count_comments: false, foldable_types: []); end

  sig { returns(Integer) }
  def calculate; end
end

module RuboCop::Cop::MethodComplexity
  sig { params(body: RuboCop::AST::Node).returns(Integer) }
  def complexity(body); end
end

module RuboCop::Cop::Metrics::Utils::RepeatedCsendDiscount
  sig { void }
  def reset_repeated_csend; end
end

class RuboCop::Cop::Metrics::CyclomaticComplexity < RuboCop::Cop::Base
  include RuboCop::Cop::MethodComplexity
  include RuboCop::Cop::Metrics::Utils::RepeatedCsendDiscount
end

class RuboCop::Cop::Metrics::PerceivedComplexity < RuboCop::Cop::Metrics::CyclomaticComplexity; end

class RuboCop::Cop::Metrics::BlockNesting < RuboCop::Cop::Base
  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def consider_node?(node); end

  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def count_if_block?(node); end
end

class RuboCop::Cop::Metrics::Utils::AbcSizeCalculator
  sig { params(node: RuboCop::AST::Node, discount_repeated_attributes: T::Boolean).returns([Float, String]) }
  def self.calculate(node, discount_repeated_attributes: false); end
end
