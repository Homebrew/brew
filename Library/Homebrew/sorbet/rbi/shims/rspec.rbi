# typed: strict

class RSpec::Core::ExampleGroup
  include RSpec::Matchers
  include RSpec::Mocks::ExampleMethods
  include RSpec::SharedContext
  include RuboCop::RSpec::ExpectOffense
  extend RuboCop::RSpec::ExpectOffense

  # RSpec::Mocks::ExampleMethods::ExpectHost#expect(target) shadows
  # RSpec::Matchers#expect(value = T.unsafe(nil), &block) in the MRO.
  # Explicitly define the correct signature here so both the value form
  # and the block-only form are accepted.
  # https://github.com/rspec/rspec/blob/rspec-expectations-v3.13.5/rspec-expectations/lib/rspec/expectations/syntax.rb#L72-L74
  def expect(value = T.unsafe(nil), &block); end
end
