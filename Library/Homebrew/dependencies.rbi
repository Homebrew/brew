# typed: strict

class Dependencies < SimpleDelegator
  include Enumerable
  include Kernel

  # This is a workaround to enable `alias eql? ==`
  # @see https://github.com/sorbet/sorbet/issues/2378#issuecomment-569474238
  sig { params(other: BasicObject).returns(T::Boolean) }
  def ==(other); end

  sig { params(blk: T.proc.params(arg0: Dependency).void).returns(T.self_type) }
  sig { returns(T::Enumerator[Dependency]) }
  def each(&blk); end

  sig { params(blk: T.proc.params(arg0: Dependency).returns(T::Boolean)).returns(T::Array[Dependency]) }
  sig { returns(T::Enumerator[Dependency]) }
  def select(&blk); end
end

class Requirements < SimpleDelegator
  include Enumerable
  include Kernel

  sig { params(blk: T.proc.params(arg0: Requirement).void).returns(T.self_type) }
  sig { returns(T::Enumerator[Requirement]) }
  def each(&blk); end

  sig { params(blk: T.proc.params(arg0: Requirement).returns(T::Boolean)).returns(T::Array[Requirement]) }
  sig { returns(T::Enumerator[Requirement]) }
  def select(&blk); end
end
