# frozen_string_literal: true

module Gem::SafeMarshal::Visitors
  class Visitor
    def visit(target)
      send DISPATCH.fetch(target.class), target
    end

    private

    DISPATCH = Gem::SafeMarshal::Elements.constants.each_with_object({}) do |c, h|
      next if c == :Element

      klass = Gem::SafeMarshal::Elements.const_get(c)
      h[klass] = :"visit_#{klass.name.gsub("::", "_")}"
      h.default = :visit_unknown_element
    end.compare_by_identity.freeze
    private_constant :DISPATCH

    def visit_unknown_element(e)
      raise ArgumentError, "Attempting to visit unknown element #{e.inspect}"
    end

    def visit_Gem_SafeMarshal_Elements_Array(target)
      target.elements.each {|e| visit(e) }
    end

    def visit_Gem_SafeMarshal_Elements_Bignum(target); end
    def visit_Gem_SafeMarshal_Elements_False(target); end
    def visit_Gem_SafeMarshal_Elements_Float(target); end

    def visit_Gem_SafeMarshal_Elements_Hash(target)
      target.pairs.each do |k, v|
        visit(k)
        visit(v)
      end
    end

    def visit_Gem_SafeMarshal_Elements_HashWithDefaultValue(target)
      visit_Gem_SafeMarshal_Elements_Hash(target)
      visit(target.default)
    end

    def visit_Gem_SafeMarshal_Elements_Integer(target); end
    def visit_Gem_SafeMarshal_Elements_Nil(target); end

    def visit_Gem_SafeMarshal_Elements_Object(target)
      visit(target.name)
    end

    def visit_Gem_SafeMarshal_Elements_ObjectLink(target); end
    def visit_Gem_SafeMarshal_Elements_String(target); end
    def visit_Gem_SafeMarshal_Elements_Symbol(target); end
    def visit_Gem_SafeMarshal_Elements_SymbolLink(target); end
    def visit_Gem_SafeMarshal_Elements_True(target); end

    def visit_Gem_SafeMarshal_Elements_UserDefined(target)
      visit(target.name)
    end

    def visit_Gem_SafeMarshal_Elements_UserMarshal(target)
      visit(target.name)
      visit(target.data)
    end

    def visit_Gem_SafeMarshal_Elements_WithIvars(target)
      visit(target.object)
      target.ivars.each do |k, v|
        visit(k)
        visit(v)
      end
    end
  end
end
