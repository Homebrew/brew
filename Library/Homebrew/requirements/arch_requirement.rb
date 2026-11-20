# typed: strict
# frozen_string_literal: true

require "requirement"

# A requirement on a specific architecture.
class ArchRequirement < Requirement
  Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

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

  sig { override.params(bottle_tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def platform_supported?(bottle_tag)
    Utils::Bottles::Tag.new(system: bottle_tag.system, arch: @arch || :dunno).standardized_arch ==
      bottle_tag.standardized_arch
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
