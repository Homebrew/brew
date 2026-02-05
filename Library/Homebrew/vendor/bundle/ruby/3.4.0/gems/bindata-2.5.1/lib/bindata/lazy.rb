module BinData
  # A LazyEvaluator is bound to a data object.  The evaluator will evaluate
  # lambdas in the context of this data object.  These lambdas
  # are those that are passed to data objects as parameters, e.g.:
  #
  #    BinData::String.new(value: -> { %w(a test message).join(" ") })
  #
  # As a shortcut, :foo is the equivalent of lambda { foo }.
  #
  # When evaluating lambdas, unknown methods are resolved in the context of the
  # parent of the bound data object.  Resolution is attempted firstly as keys
  # in #parameters, and secondly as methods in this parent.  This
  # resolution propagates up the chain of parent data objects.
  #
  # An evaluation will recurse until it returns a result that is not
  # a lambda or a symbol.
  #
  # This resolution process makes the lambda easier to read as we just write
  # <tt>field</tt> instead of <tt>obj.field</tt>.
  class LazyEvaluator

    # Creates a new evaluator.  All lazy evaluation is performed in the
    # context of +obj+.
    def initialize(obj)
      @obj = obj
    end

    def lazy_eval(val, overrides = nil)
      @overrides = overrides if overrides
      if val.is_a? Symbol
        __send__(val)
      elsif callable?(val)
        instance_exec(&val)
      else
        val
      end
    end

    # Returns a LazyEvaluator for the parent of this data object.
    def parent
      if @obj.parent
        @obj.parent.lazy_evaluator
      else
        nil
      end
    end

    # Returns the index of this data object inside it's nearest container
    # array.
    def index
      return @overrides[:index] if defined?(@overrides) && @overrides.key?(:index)

      child = @obj
      parent = @obj.parent
      while parent
        if parent.respond_to?(:find_index_of)
          return parent.find_index_of(child)
        end
        child = parent
        parent = parent.parent
      end
      raise NoMethodError, "no index found"
    end

    def method_missing(symbol, *args)
      return @overrides[symbol] if defined?(@overrides) && @overrides.key?(symbol)

      if @obj.parent
        eval_symbol_in_parent_context(symbol, args)
      else
        super
      end
    end

    #---------------
    private

    def eval_symbol_in_parent_context(symbol, args)
      result = resolve_symbol_in_parent_context(symbol, args)
      recursively_eval(result, args)
    end

    def resolve_symbol_in_parent_context(symbol, args)
      obj_parent = @obj.parent

      if obj_parent.has_parameter?(symbol)
        obj_parent.get_parameter(symbol)
      elsif obj_parent.safe_respond_to?(symbol, true)
        obj_parent.__send__(symbol, *args)
      else
        symbol
      end
    end

    def recursively_eval(val, args)
      if val.is_a?(Symbol)
        parent.__send__(val, *args)
      elsif callable?(val)
        parent.instance_exec(&val)
      else
        val
      end
    end

    def callable?(obj)
      Proc === obj || Method === obj || UnboundMethod === obj
    end
  end
end
