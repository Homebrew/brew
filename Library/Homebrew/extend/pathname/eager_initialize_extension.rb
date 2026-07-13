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

  sig { params(args: T.untyped).void }
  def initialize(*args)
    @magic_number = T.let(nil, NilClass)
    @file_type = T.let(nil, NilClass)
    @zipinfo = T.let(nil, NilClass)
    @which_install_info = T.let(nil, NilClass)
    @disk_usage = T.let(nil, NilClass)
    @file_count = T.let(nil, NilClass)
    super
  end
end
