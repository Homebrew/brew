# typed: true
# frozen_string_literal: true

require "compilers"

# Combination of C++ standard library and compiler.
class CxxStdlib
  def self.create(type, compiler)
    raise ArgumentError, "Invalid C++ stdlib type: #{type}" if type && [:libstdcxx, :libcxx].exclude?(type)

    CxxStdlib.new(type, compiler)
  end

  attr_reader :type, :compiler

  def initialize(type, compiler)
    @type = type
    @compiler = compiler.to_sym
  end

  def type_string
    type.to_s.gsub(/cxx$/, "c++")
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{compiler} #{type}>"
  end
end
