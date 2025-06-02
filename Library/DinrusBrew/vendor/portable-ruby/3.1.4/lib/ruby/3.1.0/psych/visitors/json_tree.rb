# frozen_string_literal: true
require_relative '../json/ruby_events'

module Psych
  module Visitors
    class JSONTree < YAMLTree
      include Psych::JSON::RubyEvents

      def self.create options = {}
        emitter = Psych::JSON::TreeBuilder.new
        class_loader = ClassLoader.new
        ss           = ScalarScanner.new class_loader
        new(emitter, ss, options)
      end

      def accept target
        if target.respond_to?(:encode_with)
          dump_coder target
        else
          send(@dispatch_cache[target.class], target)
        end
      end
    end
  end
end
