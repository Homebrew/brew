# typed: strict

class RSpec::Core::ExampleGroup
  extend RSpec::Matchers::DSL

  include CopHelper
  include RSpec::SharedContext
  include RSpec::Matchers
  include RSpec::Mocks::ExampleMethods
  include RuboCop::RSpec::ExpectOffense
  include Test::Helper::Cask
  include Test::Helper::Fixtures
  include Test::Helper::Formula
  include Test::Helper::IntegrationTest
  include Test::Helper::MkTmpDir
  include Test::Helper::Subcommand

  # The rspec-core RBI declares these without any `T.proc.bind`, so Sorbet infers
  # `self` inside example and hook blocks as the example group class rather than
  # an instance of it. That makes every instance method (`expect`, the matchers
  # and the `Test::Helper::*` helpers included above) appear to be undefined.
  # These cannot be deduplicated with `T.type_alias` because Sorbet rejects
  # `bind` inside a type alias.
  class << self
    sig { params(all_args: T.anything, block: T.nilable(T.proc.bind(T.attached_class).void)).void }
    def example(*all_args, &block); end

    sig { params(all_args: T.anything, block: T.nilable(T.proc.bind(T.attached_class).void)).void }
    def it(*all_args, &block); end

    sig { params(all_args: T.anything, block: T.nilable(T.proc.bind(T.attached_class).void)).void }
    def specify(*all_args, &block); end

    # Hooks are yielded the running example.
    sig {
      params(
        args:  T.anything,
        block: T.nilable(T.proc.bind(T.attached_class).params(example: RSpec::Core::Example).void),
      ).void
    }
    def after(*args, &block); end

    sig {
      params(
        args:  T.anything,
        block: T.nilable(T.proc.bind(T.attached_class).params(example: RSpec::Core::Example).void),
      ).void
    }
    def before(*args, &block); end

    # `around` is yielded a `Procsy` so that it can call `run` on it.
    sig {
      params(
        args:  T.anything,
        block: T.nilable(T.proc.bind(T.attached_class).params(example: RSpec::Core::Example::Procsy).void),
      ).void
    }
    def around(*args, &block); end

    sig {
      params(
        name:  T.any(String, Symbol),
        block: T.nilable(T.proc.bind(T.attached_class).returns(T.anything)),
      ).void
    }
    def let(name, &block); end

    sig {
      params(
        name:  T.nilable(T.any(String, Symbol)),
        block: T.nilable(T.proc.bind(T.attached_class).returns(T.anything)),
      ).void
    }
    def subject(name = nil, &block); end
  end
end

# The rspec-mocks RBI defines `ExpectHost#expect(target)` with a required
# argument and no block, which conflicts with the block form `expect { ... }`
# required by matchers like `raise_error`, `output`, `change`, etc.
# Override it to match the rspec-expectations signature.
module RSpec::Mocks::ExampleMethods::ExpectHost
  sig { params(value: T.untyped, block: T.nilable(T.proc.void)).returns(T.untyped) }
  def expect(value = T.unsafe(nil), &block); end
end

# Custom matcher bodies are class-evaluated on a new `Matcher` subclass, so
# `self` is the matcher class, where the `RSpec::Matchers::DSL::Macros` methods
# below are defined.
module RSpec::Matchers::DSL
  sig {
    params(
      name:         T.any(String, Symbol),
      declarations: T.proc.bind(T.class_of(RSpec::Matchers::DSL::Matcher)).void,
    ).void
  }
  def define(name, &declarations); end

  sig {
    params(
      name:         T.any(String, Symbol),
      declarations: T.proc.bind(T.class_of(RSpec::Matchers::DSL::Matcher)).void,
    ).void
  }
  def matcher(name, &declarations); end
end

# Conversely, the blocks those macros take are instance-evaluated on the matcher,
# so `self` is a `Matcher`. `match` must be redeclared here so that it is not
# shadowed by `RSpec::Matchers#match`, which takes a required argument. Both
# blocks are yielded the value under test, which matcher bodies introspect
# dynamically, so it cannot be narrowed beyond `T.untyped`.
module RSpec::Matchers::DSL::Macros
  sig {
    params(
      definition: T.proc.bind(RSpec::Matchers::DSL::Matcher).params(actual: T.untyped).returns(T.anything),
    ).void
  }
  def failure_message(&definition); end

  sig {
    params(
      options:     T.nilable(T::Hash[Symbol, T.anything]),
      match_block: T.proc.bind(RSpec::Matchers::DSL::Matcher).params(actual: T.untyped).returns(T.anything),
    ).void
  }
  def match(options = nil, &match_block); end
end
