# typed: strict
# frozen_string_literal: true

require "livecheck"

class Livecheck
  # Evaluation and declaration tracking for a package or resource's livecheck block.
  module DSL
    sig { returns(T::Boolean) }
    def livecheck_defined? = @livecheck_defined == true

    private

    sig { params(spec: Livecheck, block: T.nilable(T.proc.bind(Livecheck).void)).returns(Livecheck) }
    def configure_livecheck(spec, &block)
      if block
        @livecheck_defined = T.let(true, T.nilable(TrueClass))
        spec.instance_eval(&block)
      end
      spec
    end
  end
end
