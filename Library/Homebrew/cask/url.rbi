# typed: strict

module Cask
  class URL
    include Kernel

    # TODO: Generate this

    sig { returns(T.any(T::Class[T.anything], Symbol, NilClass)) }
    def using; end

    sig { returns(T.nilable(T.any(URI::Generic, String))) }
    def referer; end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def specs; end

    sig { returns(T.nilable(T.any(Symbol, String))) }
    def user_agent; end

    sig { returns(T.nilable(String)) }
    def verified; end
  end
end
