# typed: strong
# frozen_string_literal: true

require "compilers"

# Combination of C++ standard library and compiler.
class CxxStdlib
  sig { params(type: T.nilable(Symbol), compiler: T.any(Symbol, String)).returns(CxxStdlib) }
  def self.create(type, compiler)
    raise ArgumentError, "Invalid C++ stdlib type: #{type}" if type && [:libstdcxx, :libcxx].exclude?(type)

    CxxStdlib.new(type, compiler)
  end

  sig { returns(T.nilable(Symbol)) }
  attr_reader :type

  sig { returns(Symbol) }
  attr_reader :compiler

  sig { params(type: T.nilable(Symbol), compiler: T.any(Symbol, String)).void }
  def initialize(type, compiler)
    @type = type
    @compiler = T.let(compiler.to_sym, Symbol)
  end

  sig { returns(String) }
  def type_string
    type.to_s.gsub(/cxx$/, "c++")
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{compiler} #{type}>"
  end
end
