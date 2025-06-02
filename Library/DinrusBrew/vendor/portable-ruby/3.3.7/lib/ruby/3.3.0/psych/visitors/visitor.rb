# frozen_string_literal: true
module Psych
  module Visitors
    class Visitor
      def accept target
        visit target
      end

      private

      # @api private
      def self.dispatch_cache
        Hash.new do |hash, klass|
          hash[klass] = :"visit_#{klass.name.gsub('::', '_')}"
        end.compare_by_identity
      end

      if defined?(Ractor)
        def dispatch
          @dispatch_cache ||= (Ractor.current[:Psych_Visitors_Visitor] ||= Visitor.dispatch_cache)
        end
      else
        DISPATCH = dispatch_cache
        def dispatch
          DISPATCH
        end
      end

      def visit target
        send dispatch[target.class], target
      end
    end
  end
end
