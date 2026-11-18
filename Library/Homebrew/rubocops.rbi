# typed: strict
# frozen_string_literal: true

class RuboCop::Cop::VariableForce::Variable
  sig { returns(RuboCop::AST::Node) }
  def declaration_node; end
end

class RuboCop::Cop::VariableForce::VariableTable < Object; end

# Sorbet does not see `public :name` re-exposing an inherited private method.
class RuboCop::Cop::Homebrew::SingleUseMethod::CyclomaticComplexityScore
  sig { params(body: RuboCop::AST::Node).returns(Integer) }
  def complexity(body); end
end

class RuboCop::Cop::Homebrew::SingleUseMethod::PerceivedComplexityScore
  sig { params(body: RuboCop::AST::Node).returns(Integer) }
  def complexity(body); end
end

class RuboCop::Cop::Homebrew::SingleUseMethod::BlockNestingScore
  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def consider_node?(node); end

  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def count_if_block?(node); end
end
