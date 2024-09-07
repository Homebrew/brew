# typed: strict

module EnvActivation
  include SharedEnvExtension
end

# @!visibility private
class Sorbet
  module Private
    module Static
      class ENVClass
        include EnvActivation
      end
    end
  end
end
