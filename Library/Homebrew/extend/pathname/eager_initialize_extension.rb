# typed: strict
# frozen_string_literal: true

# Eagerly initialises {Pathname}'s lazy memoised ivars so every instance
# shares one object shape, avoiding Ruby's shape-variation warning.
#
# Any new `@x ||= ...` ivar added to {Pathname} or its mixed-in extensions
# must also be added to `#initialize` below to keep the shape stable.
module EagerInitializeExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  # This alias hoists the `T.nilable(...)` type object out of the hot path.
  # `#initialize` runs on every {Pathname} allocation, and with runtime
  # checks disabled `T.let` discards its type argument, so evaluating
  # `T.nilable(...)` inline would rebuild the same type objects each time.
  NilableInteger = T.type_alias { T.nilable(Integer) }

  sig { params(args: T.untyped).void }
  def initialize(*args)
    @disk_usage = T.let(nil, NilableInteger)
    @file_count = T.let(nil, NilableInteger)
    super
  end
end
