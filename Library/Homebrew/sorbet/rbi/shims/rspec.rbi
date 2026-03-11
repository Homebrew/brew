# typed: strict

class RSpec::Core::ExampleGroup
  include RSpec::Matchers
  include RSpec::Mocks::ExampleMethods
  include RSpec::SharedContext
  include RuboCop::RSpec::ExpectOffense
  extend RuboCop::RSpec::ExpectOffense
end
