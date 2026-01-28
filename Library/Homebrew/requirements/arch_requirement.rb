# typed: strict
# frozen_string_literal: true

require "requirement"

# A requirement on a specific architecture.
class ArchRequirement < Requirement
  fatal true

  @arch = T.let(nil, T.nilable(Symbol))

  sig { returns(T.nilable(Symbol)) }
  attr_reader :arch

  sig { params(tags: T::Array[Symbol]).void }
  def initialize(tags)
    @arch = T.let(tags.shift, T.nilable(Symbol))
    super
  end

  satisfy(build_env: false) do
    case @arch
    when :x86_64 then Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
    when :arm64 then Hardware::CPU.arm64?
    when :arm, :intel, :ppc then Hardware::CPU.type == @arch
    end
  end

  sig { returns(String) }
  def message
    "The #{@arch} architecture is required for this software."
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: arch=#{@arch.to_s.inspect} #{tags.inspect}>"
  end

  sig { returns(String) }
  def display_s
    "#{@arch} architecture"
  end
end
