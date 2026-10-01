# typed: strict
# frozen_string_literal: true

module CompilerConstants
  # GCC 8 is the minimum version needed for `-ffile-prefix-map`.
  # Oldest GCC versions in use by LTS distros include:
  # * Ubuntu 18.04 (ESM ends 2028-04-01) - GCC 7 default, GCC 8 is available
  # * RHEL 8 (ELS ends 2032-05-31) - GCC 8 default and newer versions via gcc-toolset
  GNU_GCC_VERSIONS = %w[8 9 10 11 12 13 14 15 16].freeze
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
