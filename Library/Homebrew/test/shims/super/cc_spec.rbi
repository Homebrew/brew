# typed: strict

module CcShim
  class Cmd
    sig { params(arg0: String, args: T::Array[String]).void }
    def initialize(arg0, args); end

    sig { returns(T::Array[String]) }
    def args; end
  end
end
