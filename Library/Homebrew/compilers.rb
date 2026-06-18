# typed: strict
# frozen_string_literal: true

module CompilerConstants
  # GCC 7 - Ubuntu 18.04 (ESM ends 2028-04-01)
  # GCC 8 - RHEL 8       (ELS ends 2032-05-31)
  GNU_GCC_VERSIONS = %w[7 8 9 10 11 12 13 14 15 16].freeze
  GNU_GCC_REGEXP = /^gcc-(#{GNU_GCC_VERSIONS.join("|")})$/
  COMPILER_SYMBOL_MAP = T.let({
    "gcc"        => :gcc,
    "clang"      => :clang,
    "llvm_clang" => :llvm_clang,
  }.freeze, T::Hash[String, Symbol])

  COMPILERS = T.let((COMPILER_SYMBOL_MAP.values +
                     GNU_GCC_VERSIONS.map { |n| "gcc-#{n}" }).freeze, T::Array[T.any(String, Symbol)])
end
require "compilers/compiler_failure"
require "compilers/compiler_selector"

require "extend/os/compilers"
