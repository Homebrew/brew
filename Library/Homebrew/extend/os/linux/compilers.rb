# typed: strict
# frozen_string_literal: true

class CompilerSelector
  sig { returns(String) }
  def self.preferred_gcc
    OS::LINUX_PREFERRED_GCC_COMPILER_FORMULA
  end
end
