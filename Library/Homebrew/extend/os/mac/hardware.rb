# typed: strict
# frozen_string_literal: true

module Hardware
  sig { params(version: T.nilable(Version)).returns(Symbol) }
  def self.oldest_cpu(version = nil)
    version = if version
      MacOSVersion.new(version.to_s)
    else
      MacOS.version
    end
    if CPU.arch == :arm64
      :arm_vortex_tempest
    # This cannot use a newer CPU e.g. haswell because Rosetta 2 does not
    # support AVX instructions in bottles:
    #   https://github.com/Homebrew/homebrew-core/issues/67713
    elsif version >= :ventura
      :westmere
    elsif version >= :mojave
      :nehalem
    else
      generic_oldest_cpu
    end
  end
end
