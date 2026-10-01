# typed: strict

# Sorbet's core RBI for `Fiber` is missing `initialize` so does not know
# `Fiber.new` takes a block.
class Fiber
  sig { params(blk: T.proc.returns(T.untyped)).void }
  def initialize(&blk); end
end
