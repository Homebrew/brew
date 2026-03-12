# typed: strict

class RSpec::Core::ExampleGroup
  # RSpec::Mocks::ExampleMethods includes ExpectHost which defines expect(target)
  # with a required argument. Including RSpec::Matchers last places it higher in the
  # MRO so RSpec::Matchers#expect(value = T.unsafe(nil), &block) takes precedence,
  # allowing the block-only form: expect { }.not_to raise_error
  # https://github.com/rspec/rspec/blob/rspec-expectations-v3.13.5/rspec-expectations/lib/rspec/expectations/syntax.rb#L72-L74
  include RSpec::Mocks::ExampleMethods
  include RSpec::SharedContext
  include RuboCop::RSpec::ExpectOffense
  extend RuboCop::RSpec::ExpectOffense
  include RSpec::Matchers
end
