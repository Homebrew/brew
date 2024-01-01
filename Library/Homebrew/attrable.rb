# typed: strict
# frozen_string_literal: true

module Attrable
  sig { params(attrs: Symbol).void }
  def attr_predicate(*attrs)
    attrs.each do |attr|
      define_method attr do
        instance_variable_get("@#{attr.to_s.sub(/\?$/, "")}") == true
      end
    end
  end

  sig { params(attrs: Symbol).void }
  def attr_rw(*attrs)
    attrs.each do |attr|
      define_method attr do |val = nil|
        val.nil? ? instance_variable_get(:"@#{attr}") : instance_variable_set(:"@#{attr}", val)
      end
    end
  end
end
