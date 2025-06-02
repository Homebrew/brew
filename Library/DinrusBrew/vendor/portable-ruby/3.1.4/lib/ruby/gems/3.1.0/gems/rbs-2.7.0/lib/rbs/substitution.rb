# frozen_string_literal: true

module RBS
  class Substitution
    attr_reader :mapping
    attr_accessor :instance_type

    def empty?
      mapping.empty? && instance_type.nil?
    end

    def initialize()
      @mapping = {}
    end

    def add(from:, to:)
      mapping[from] = to
    end

    def self.build(variables, types, instance_type: nil, &block)
      unless variables.size == types.size
        raise "Broken substitution: variables=#{variables}, types=#{types}"
      end

      mapping = variables.zip(types).to_h

      self.new.tap do |subst|
        mapping.each do |v, t|
          type = block_given? ? yield(t) : t
          subst.add(from: v, to: type)
        end

        subst.instance_type = instance_type
      end
    end

    def apply(ty)
      case ty
      when Types::Variable
        # @type var ty: Types::Variable
        mapping[ty.name] || ty
      when Types::Bases::Instance
        if t = instance_type
          t
        else
          ty
        end
      else
        ty
      end
    end

    def without(*vars)
      Substitution.new.tap do |subst|
        subst.mapping.merge!(mapping)
        vars.each do |var|
          subst.mapping.delete(var)
        end

        subst.instance_type = self.instance_type
      end
    end
  end
end
