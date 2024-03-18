# frozen_string_literal: true
# typed: true

class T::Private::Methods::Signature
  attr_reader :method, :method_name, :arg_types, :kwarg_types, :block_type, :block_name,
              :rest_type, :rest_name, :keyrest_type, :keyrest_name, :bind,
              :return_type, :mode, :req_arg_count, :req_kwarg_names, :has_rest, :has_keyrest,
              :check_level, :parameters, :on_failure, :override_allow_incompatible,
              :defined_raw

  UNNAMED_REQUIRED_PARAMETERS = [[:req]].freeze

  def self.new_untyped(method:, mode: T::Private::Methods::Modes.untyped, parameters: method.parameters)
    # Using `NotTyped` ensures we'll get an error if we ever try validation on these.
    not_typed = T::Private::Types::NotTyped::INSTANCE
    raw_return_type = not_typed
    # Map missing parameter names to "argN" positionally
    parameters = parameters.each_with_index.map do |(param_kind, param_name), index|
      [param_kind, param_name || "arg#{index}"]
    end
    raw_arg_types = {}
    parameters.each do |_, param_name|
      raw_arg_types[param_name] = not_typed
    end

    self.new(
      method: method,
      method_name: method.name,
      raw_arg_types: raw_arg_types,
      raw_return_type: raw_return_type,
      bind: nil,
      mode: mode,
      check_level: :never,
      parameters: parameters,
      on_failure: nil,
    )
  end

  def initialize(method:, method_name:, raw_arg_types:, raw_return_type:, bind:, mode:, check_level:, on_failure:, parameters: method.parameters, override_allow_incompatible: false, defined_raw: false)
    @method = method
    @method_name = method_name
    @block_type = nil
    @block_name = nil
    @rest_type = nil
    @rest_name = nil
    @keyrest_type = nil
    @keyrest_name = nil
    @return_type = T::Utils.coerce(raw_return_type)
    @bind = bind ? T::Utils.coerce(bind) : bind
    @mode = mode
    @check_level = check_level
    @has_rest = false
    @has_keyrest = false
    @parameters = parameters
    @on_failure = on_failure
    @override_allow_incompatible = override_allow_incompatible
    @defined_raw = defined_raw

    # Use T.untyped in lieu of T.nilable to try to avoid unnecessary allocations.
    arg_types = T.let(nil, T.untyped)
    kwarg_types = T.let(nil, T.untyped)
    req_arg_count = 0
    req_kwarg_names = T.let(nil, T.untyped)

    # If sig params are declared but there is a single parameter with a missing name
    # **and** the method ends with a "=", assume it is a writer method generated
    # by attr_writer or attr_accessor
    writer_method = !(raw_arg_types.size == 1 && raw_arg_types.key?(nil)) && parameters == UNNAMED_REQUIRED_PARAMETERS && method_name[-1] == "="
    # For writer methods, map the single parameter to the method name without the "=" at the end
    parameters = [[:req, method_name[0...-1].to_sym]] if writer_method
    is_name_missing = parameters.any? {|_, name| !raw_arg_types.key?(name)}
    if is_name_missing
      param_names = parameters.map {|_, name| name}
      missing_names = param_names - raw_arg_types.keys
      raise "The declaration for `#{method.name}` is missing parameter(s): #{missing_names.join(', ')}"
    elsif parameters.length != raw_arg_types.size
      param_names = parameters.map {|_, name| name}
      has_extra_names = parameters.count {|_, name| raw_arg_types.key?(name)} < raw_arg_types.size
      if has_extra_names
        extra_names = raw_arg_types.keys - param_names
        raise "The declaration for `#{method.name}` has extra parameter(s): #{extra_names.join(', ')}"
      end
    end

    if parameters.size != raw_arg_types.size
      raise "The declaration for `#{method.name}` has arguments with duplicate names"
    end
    i = 0
    raw_arg_types.each do |type_name, raw_type|
      param_kind, param_name = parameters[i]

      if type_name != param_name
        hint = ""
        # Ruby reorders params so that required keyword arguments
        # always precede optional keyword arguments. We can't tell
        # whether the culprit is the Ruby reordering or user error, so
        # we error but include a note
        if param_kind == :keyreq && parameters.any? {|k, _| k == :key}
          hint = "\n\nNote: Any required keyword arguments must precede any optional keyword " \
                 "arguments. If your method declaration matches your `def`, try reordering any " \
                 "optional keyword parameters to the end of the method list."
        end

        raise "Parameter `#{type_name}` is declared out of order (declared as arg number " \
              "#{i + 1}, defined in the method as arg number " \
              "#{parameters.index {|_, name| name == type_name} + 1}).#{hint}\nMethod: #{method_desc}"
      end

      type = T::Utils.coerce(raw_type)

      case param_kind
      when :req
        if (arg_types ? arg_types.length : 0) > req_arg_count
          # Note that this is actually is supported by Ruby, but it would add complexity to
          # support it here, and I'm happy to discourage its use anyway.
          #
          # If you are seeing this error and surprised by it, it's possible that you have
          # overridden the method described in the error message. For example, Rails defines
          # def self.update!(id = :all, attributes)
          # on AR models. If you have also defined `self.update!` on an AR model you might
          # see this error. The simplest resolution is to rename your method.
          raise "Required params after optional params are not supported in method declarations. Method: #{method_desc}"
        end
        (arg_types ||= []) << [param_name, type]
        req_arg_count += 1
      when :opt
        (arg_types ||= []) << [param_name, type]
      when :key, :keyreq
        (kwarg_types ||= {})[param_name] = type
        if param_kind == :keyreq
          (req_kwarg_names ||= []) << param_name
        end
      when :block
        @block_name = param_name
        @block_type = type
      when :rest
        @has_rest = true
        @rest_name = param_name
        @rest_type = type
      when :keyrest
        @has_keyrest = true
        @keyrest_name = param_name
        @keyrest_type = type
      else
        raise "Unexpected param_kind: `#{param_kind}`. Method: #{method_desc}"
      end

      i += 1
    end

    @arg_types = arg_types || EMPTY_LIST
    @kwarg_types = kwarg_types || EMPTY_HASH
    @req_arg_count = req_arg_count
    @req_kwarg_names = req_kwarg_names || EMPTY_LIST
  end

  attr_writer :method_name
  protected :method_name=

  def as_alias(alias_name)
    new_sig = clone
    new_sig.method_name = alias_name
    new_sig
  end

  def arg_count
    @arg_types.length
  end

  def kwarg_names
    @kwarg_types.keys
  end

  def owner
    @method.owner
  end

  def dsl_method
    "#{@mode}_method"
  end

  # @return [Hash] a mapping like `{arg_name: [val, type], ...}`, for only those args actually present.
  def each_args_value_type(args)
    # Manually split out args and kwargs based on ruby's behavior. Do not try to implement this by
    # getting ruby to determine the kwargs for you (e.g., by defining this method to take *args and
    # **kwargs). That won't work, because ruby's behavior for determining kwargs is dependent on the
    # the other parameters in the method definition, and our method definition here doesn't (and
    # can't) match the definition of the method we're validating. In addition, Ruby has a bug that
    # causes forwarding **kwargs to do the wrong thing: see https://bugs.ruby-lang.org/issues/10708
    # and https://bugs.ruby-lang.org/issues/11860.
    args_length = args.length
    if (args_length > @req_arg_count) && (!@kwarg_types.empty? || @has_keyrest) && args[-1].is_a?(Hash)
      kwargs = args[-1]
      args_length -= 1
    else
      kwargs = EMPTY_HASH
    end

    if !@has_rest && ((args_length < @req_arg_count) || (args_length > @arg_types.length))
      expected_str = @req_arg_count.to_s
      if @arg_types.length != @req_arg_count
        expected_str += "..#{@arg_types.length}"
      end
      raise ArgumentError.new("wrong number of arguments (given #{args_length}, expected #{expected_str})")
    end

    begin
      it = 0

      # Process given pre-rest args. When there are no rest args,
      # this is just the given number of args.
      while it < args_length && it < @arg_types.length
        yield @arg_types[it][0], args[it], @arg_types[it][1]
        it += 1
      end

      if @has_rest
        rest_count = args_length - @arg_types.length
        rest_count = 0 if rest_count.negative?

        rest_count.times do
          yield @rest_name, args[it], @rest_type
          it += 1
        end
      end
    end

    kwargs.each do |name, val|
      type = @kwarg_types[name]
      if !type && @has_keyrest
        type = @keyrest_type
      end

      yield name, val, type if type
    end
  end

  def method_desc
    loc = if @method.source_location
      @method.source_location.join(':')
    else
      "<unknown location>"
    end
    "#{@method} at #{loc}"
  end

  def force_type_init
    @arg_types.each {|_, type| type.build_type}
    @kwarg_types.each {|_, type| type.build_type}
    @block_type&.build_type
    @rest_type&.build_type
    @keyrest_type&.build_type
    @return_type.build_type
  end

  EMPTY_LIST = [].freeze
  EMPTY_HASH = {}.freeze
end
