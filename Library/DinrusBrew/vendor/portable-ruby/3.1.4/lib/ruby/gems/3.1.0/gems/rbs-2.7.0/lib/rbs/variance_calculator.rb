# frozen_string_literal: true

module RBS
  class VarianceCalculator
    class Result
      attr_reader :result

      def initialize(variables:)
        @result = {}
        variables.each do |x|
          result[x] = :unused
        end
      end

      def covariant(x)
        case result[x]
        when :unused
          result[x] = :covariant
        when :contravariant
          result[x] = :invariant
        end
      end

      def contravariant(x)
        case result[x]
        when :unused
          result[x] = :contravariant
        when :covariant
          result[x] = :invariant
        end
      end

      def invariant(x)
        result[x] = :invariant
      end

      def each(&block)
        result.each(&block)
      end

      def include?(name)
        result.key?(name)
      end

      def compatible?(var, with_annotation:)
        variance = result[var]

        case
        when variance == :unused
          true
        when with_annotation == :invariant
          true
        when variance == with_annotation
          true
        else
          false
        end
      end

      def incompatible?(params)
        # @type set: Hash[Symbol]
        set = Set[]

        params.each do |param|
          unless compatible?(param.name, with_annotation: param.variance)
            set << param.name
          end
        end

        unless set.empty?
          set
        end
      end
    end

    attr_reader :builder

    def initialize(builder:)
      @builder = builder
    end

    def env
      builder.env
    end

    def in_method_type(method_type:, variables:)
      result = Result.new(variables: variables)

      function(method_type.type, result: result, context: :covariant)

      if block = method_type.block
        function(block.type, result: result, context: :contravariant)
      end

      result
    end

    def in_inherit(name:, args:, variables:)
      type = if name.class?
               Types::ClassInstance.new(name: name, args: args, location: nil)
             else
               Types::Interface.new(name: name, args: args, location: nil)
             end

      Result.new(variables: variables).tap do |result|
        type(type, result: result, context: :covariant)
      end
    end

    def in_type_alias(name:)
      decl = env.alias_decls[name].decl or raise
      variables = decl.type_params.each.map(&:name)
      Result.new(variables: variables).tap do |result|
        type(decl.type, result: result, context: :covariant)
      end
    end

    def type(type, result:, context:)
      case type
      when Types::Variable
        if result.include?(type.name)
          case context
          when :covariant
            result.covariant(type.name)
          when :contravariant
            result.contravariant(type.name)
          when :invariant
            result.invariant(type.name)
          end
        end
      when Types::ClassInstance, Types::Interface, Types::Alias
        NoTypeFoundError.check!(type.name,
                                env: env,
                                location: type.location)

        type_params = case type
                      when Types::ClassInstance
                        env.class_decls[type.name].type_params
                      when Types::Interface
                        env.interface_decls[type.name].decl.type_params
                      when Types::Alias
                        env.alias_decls[type.name].decl.type_params
                      end

        type.args.each.with_index do |ty, i|
          if var = type_params[i]
            case var.variance
            when :invariant
              type(ty, result: result, context: :invariant)
            when :covariant
              type(ty, result: result, context: context)
            when :contravariant
              type(ty, result: result, context: negate(context))
            end
          end
        end
      when Types::Proc
        function(type.type, result: result, context: context)
      else
        type.each_type do |ty|
          type(ty, result: result, context: context)
        end
      end
    end

    def function(type, result:, context:)
      type.each_param do |param|
        type(param.type, result: result, context: negate(context))
      end
      type(type.return_type, result: result, context: context)
    end

    def negate(variance)
      case variance
      when :invariant
        :invariant
      when :covariant
        :contravariant
      when :contravariant
        :covariant
      else
        raise
      end
    end
  end
end
