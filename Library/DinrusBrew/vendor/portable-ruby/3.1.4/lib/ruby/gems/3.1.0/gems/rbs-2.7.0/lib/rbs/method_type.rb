# frozen_string_literal: true

module RBS
  class MethodType
    attr_reader :type_params
    attr_reader :type
    attr_reader :block
    attr_reader :location

    def initialize(type_params:, type:, block:, location:)
      @type_params = type_params
      @type = type
      @block = block
      @location = location
    end

    def ==(other)
      other.is_a?(MethodType) &&
        other.type_params == type_params &&
        other.type == type &&
        other.block == block
    end

    def to_json(state = _ = nil)
      {
        type_params: type_params,
        type: type,
        block: block,
        location: location
      }.to_json(state)
    end

    def sub(s)
      sub = s.without(*type_param_names)

      self.class.new(
        type_params: type_params.map do |param|
          param.map_type do |bound|
            bound.map_type {|ty| ty.sub(sub) }
          end
        end,
        type: type.sub(sub),
        block: block&.sub(sub),
        location: location
      )
    end

    def update(type_params: self.type_params, type: self.type, block: self.block, location: self.location)
      self.class.new(
        type_params: type_params,
        type: type,
        block: block,
        location: location
      )
    end

    def free_variables(set = Set.new)
      type.free_variables(set)
      block&.type&.free_variables(set)
      set.subtract(type_param_names)
    end

    def map_type(&block)
      self.class.new(
        type_params: type_params,
        type: type.map_type(&block),
        block: self.block&.map_type(&block),
        location: location
      )
    end

    def map_type_bound(&block)
      if type_params.empty?
        self
      else
        self.update(
          type_params: type_params.map {|param|
            param.map_type(&block)
          }
        )
      end
    end

    def each_type(&block)
      if block
        type.each_type(&block)
        self.block&.yield_self do |b|
          b.type.each_type(&block)
        end
      else
        enum_for :each_type
      end
    end

    def to_s
      block_self_binding = Types::SelfTypeBindingHelper.self_type_binding_to_s(block&.self_type)

      s = case
          when (b = block) && b.required
            "(#{type.param_to_s}) { (#{b.type.param_to_s}) #{block_self_binding}-> #{b.type.return_to_s} } -> #{type.return_to_s}"
          when b = block
            "(#{type.param_to_s}) ?{ (#{b.type.param_to_s}) #{block_self_binding}-> #{b.type.return_to_s} } -> #{type.return_to_s}"
          else
            "(#{type.param_to_s}) -> #{type.return_to_s}"
          end

      if type_params.empty?
        s
      else
        "[#{type_params.join(", ")}] #{s}"
      end
    end

    def type_param_names
      type_params.map(&:name)
    end
  end
end
