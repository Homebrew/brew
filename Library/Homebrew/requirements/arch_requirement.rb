# typed: true
# frozen_string_literal: true

require "requirement"

# A requirement on a specific architecture.
#
# @api private
class ArchRequirement < Requirement
  extend T::Sig

  fatal true

  attr_reader :arch

  def initialize(tags)
    @arch = []
    tags.each do |tag|
      if Hardware::CPU::ALL_ARCHS.include? tag
        @arch.append(tag)
        tags.delete(tag)
      end
    end

    super(tags)
  end

  satisfy(build_env: false) do
    if @arch.is_a? Array
      next true if @arch.empty?

      satisfied = T.let(false, T::Boolean)
      @arch.each do |arch|
        satisfied = satisfies_arch(arch)
        break if satisfied
      end

      next satisfied
    elsif @arch.nil?
      next true
    end
    satisfies_arch(@arch)
  end

  sig { params(arch: Symbol).returns(T::Boolean) }
  def satisfies_arch(arch)
    case arch
    when :x86_64 then Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
    when :arm64 then Hardware::CPU.arm? && Hardware::CPU.is_64_bit?
    when :arm, :intel, :ppc then Hardware::CPU.type == arch
    end
  end

  sig { returns(String) }
  def message
    "One of #{@arch} architectures is required for this software."
  end

  def inspect
    "#<#{self.class.name}: arch=#{@arch.to_s.inspect} #{tags.inspect}>"
  end

  sig { returns(String) }
  def display_s
    "#{@arch} architecture"
  end
end
