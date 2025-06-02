# frozen_string_literal: true

module RBS
  module Test
    module Errors
      ArgumentTypeError =
        Struct.new(:klass, :method_name, :method_type, :param, :value, keyword_init: true)
      BlockArgumentTypeError =
        Struct.new(:klass, :method_name, :method_type, :param, :value, keyword_init: true)
      ArgumentError =
        Struct.new(:klass, :method_name, :method_type, keyword_init: true)
      BlockArgumentError =
        Struct.new(:klass, :method_name, :method_type, keyword_init: true)
      ReturnTypeError =
        Struct.new(:klass, :method_name, :method_type, :type, :value, keyword_init: true)
      BlockReturnTypeError =
        Struct.new(:klass, :method_name, :method_type, :type, :value, keyword_init: true)

      UnexpectedBlockError = Struct.new(:klass, :method_name, :method_type, keyword_init: true)
      MissingBlockError = Struct.new(:klass, :method_name, :method_type, keyword_init: true)

      UnresolvedOverloadingError = Struct.new(:klass, :method_name, :method_types, keyword_init: true)

      def self.format_param(param)
        if param.name
          "`#{param.type}` (#{param.name})"
        else
          "`#{param.type}`"
        end
      end

      def self.inspect_(obj)
        if obj.respond_to?(:inspect)
          obj.inspect
        else
          Test::INSPECT.bind(obj).call     # For the case inspect is not defined (like BasicObject)
        end
      end

      def self.to_string(error)
        method = "#{error.klass.name}#{error.method_name}"
        case error
        when ArgumentTypeError
          "[#{method}] ArgumentTypeError: expected #{format_param error.param} but given `#{inspect_(error.value)}`"
        when BlockArgumentTypeError
          "[#{method}] BlockArgumentTypeError: expected #{format_param error.param} but given `#{inspect_(error.value)}`"
        when ArgumentError
          "[#{method}] ArgumentError: expected method type #{error.method_type}"
        when BlockArgumentError
          "[#{method}] BlockArgumentError: expected method type #{error.method_type}"
        when ReturnTypeError
          "[#{method}] ReturnTypeError: expected `#{error.type}` but returns `#{inspect_(error.value)}`"
        when BlockReturnTypeError
          "[#{method}] BlockReturnTypeError: expected `#{error.type}` but returns `#{inspect_(error.value)}`"
        when UnexpectedBlockError
          "[#{method}] UnexpectedBlockError: unexpected block is given for `#{error.method_type}`"
        when MissingBlockError
          "[#{method}] MissingBlockError: required block is missing for `#{error.method_type}`"
        when UnresolvedOverloadingError
          "[#{method}] UnresolvedOverloadingError: couldn't find a suitable overloading"
        else
          raise "Unexpected error: #{inspect_(error)}"
        end
      end
    end
  end
end
