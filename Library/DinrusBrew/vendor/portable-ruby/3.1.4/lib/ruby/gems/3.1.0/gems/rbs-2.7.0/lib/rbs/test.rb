# frozen_string_literal: true

require "securerandom"
require "rbs/test/observer"
require "rbs/test/spy"
require "rbs/test/errors"
require "rbs/test/type_check"
require "rbs/test/tester"
require "rbs/test/hook"
require "rbs/test/setup_helper"

module RBS
  module Test
    IS_AP = Kernel.instance_method(:is_a?)
    DEFINE_METHOD = Module.instance_method(:define_method)
    INSTANCE_EVAL = BasicObject.instance_method(:instance_eval)
    INSTANCE_EXEC = BasicObject.instance_method(:instance_exec)
    METHOD = Kernel.instance_method(:method)
    CLASS = Kernel.instance_method(:class)
    SINGLETON_CLASS = Kernel.instance_method(:singleton_class)
    PP = Kernel.instance_method(:pp)
    INSPECT = Kernel.instance_method(:inspect)
    METHODS = Kernel.instance_method(:methods)

    class ArgumentsReturn
      attr_reader :arguments
      attr_reader :exit_value
      attr_reader :exit_type

      def initialize(arguments:, exit_value:, exit_type:)
        @arguments = arguments
        @exit_value = exit_value
        @exit_type = exit_type
      end

      def self.return(arguments:, value:)
        new(arguments: arguments, exit_value: value, exit_type: :return)
      end

      def self.exception(arguments:, exception:)
        new(arguments: arguments, exit_value: exception, exit_type: :exception)
      end

      def self.break(arguments:)
        new(arguments: arguments, exit_value: nil, exit_type: :break)
      end

      def return_value
        raise unless exit_type == :return
        exit_value
      end

      def exception
        raise unless exit_type == :exception
        exit_value
      end

      def return?
        exit_type == :return
      end

      def exception?
        exit_type == :exception
      end

      def break?
        exit_type == :break
      end
    end

    CallTrace = Struct.new(:method_name, :method_call, :block_calls, :block_given, keyword_init: true)

    class <<self
      attr_accessor :suffix

      def reset_suffix
        self.suffix = "RBS_TEST_#{SecureRandom.hex(3)}"
      end
    end

    reset_suffix

    if ::UnboundMethod.instance_methods.include?(:bind_call)
      def self.call(receiver, method, *args, &block)
        method.bind_call(receiver, *args, &block)
      end
    else
      def self.call(receiver, method, *args, &block)
        method.bind(receiver).call(*args, &block)
      end
    end
  end
end

unless ::Module.private_instance_methods.include?(:ruby2_keywords)
  class Module
    private
    def ruby2_keywords(*)
    end
  end
end

unless ::Proc.instance_methods.include?(:ruby2_keywords)
  class Proc
    def ruby2_keywords
      self
    end
  end
end
