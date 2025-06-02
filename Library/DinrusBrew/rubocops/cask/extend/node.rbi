# typed: strict

class RuboCop::AST::Node
  sig { returns(T.nilable(RuboCop::AST::SendNode)) }
  def method_node; end

  sig { returns(T.nilable(RuboCop::AST::Node)) }
  def block_body; end

  sig { returns(T::Boolean) }
  def cask_block?; end

  sig { returns(T::Boolean) }
  def on_system_block?; end

  sig { returns(T::Boolean) }
  def arch_variable?; end

  sig { returns(T::Boolean) }
  def begin_block?; end
end
