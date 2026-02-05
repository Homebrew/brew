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
        # NOTE: This is a bit misleading, as at most only one of these can be true
        # See: EnvActivation#activate_extensions!
        include Stdenv
        include Superenv
      end
    end
  end
end
