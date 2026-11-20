# frozen_string_literal: true
# typed: true

# Every sig keeps one of these for the life of the process. At 18 or fewer instance variables an
# instance fits in a 160-byte GC slot; a 19th moves every instance to the 320-byte slot, so prefer
# deriving new state over storing it.
class T::Private::Methods::Signature
  attr_reader :method, :method_name, :arg_types, :kwarg_types, :block_type,
              :rest_type, :keyrest_type, :bind, :effective_return_type,
              :return_type, :req_arg_count, :req_kwarg_names, :on_failure

  # @flags packs, from the low bits up: mode (3 bits), check_level (2 bits),
  # override_allow_incompatible (2 bits), and defined_raw (1 bit).
  FLAG_MODES = T::Private::Methods::Modes::MODES
  FLAG_CHECK_LEVELS = T::Private::RuntimeLevels::LEVELS
  FLAG_ALLOW_INCOMPATIBLE = [false, true, :visibility].freeze
  MODE_MASK = 0b111
  CHECK_LEVEL_SHIFT = 3
  CHECK_LEVEL_MASK = 0b11
  ALLOW_INCOMPATIBLE_SHIFT = 5
  ALLOW_INCOMPATIBLE_MASK = 0b11
  DEFINED_RAW_BIT = 1 << 7
  private_constant :FLAG_MODES, :FLAG_CHECK_LEVELS, :FLAG_ALLOW_INCOMPATIBLE, :MODE_MASK,
                   :CHECK_LEVEL_SHIFT, :CHECK_LEVEL_MASK, :ALLOW_INCOMPATIBLE_SHIFT,
                   :ALLOW_INCOMPATIBLE_MASK, :DEFINED_RAW_BIT

  # T.unsafe: `UnboundMethod#parameters` lies and says `T::Array[[Symbol, Symbol]]`.
  # Sorbet can't lub tuple types, meaning that `T.any([Symbol], [Symbol,
  # Symbol])` would just be `T::Array[T.untyped]`. But Sorbet can see that
  # UNNAMED_REQUIRED_PARAMETERS, which is an array of 1-tuples, can never
  # equal an array of 2-tuples, and calls the code dead. There's no good
  # option, let's just unsafe until tuples are better and we can fix the sig.
  UNNAMED_REQUIRED_PARAMETERS = T.unsafe([[:req]].freeze)

  def self.new_untyped(method:, mode: T::Private::Methods::Modes.untyped, parameters: method.parameters)
    # Using `NotTyped` ensures we'll get an error if we ever try validation on these.
    not_typed = T::Private::Types::NotTyped::INSTANCE
    raw_return_type = not_typed
    # Map missing parameter names to "argN" positionally
    parameters = parameters.each_with_index.map do |(param_kind, param_name), index|
      [param_kind, T.unsafe(param_name) || "arg#{index}".to_sym]
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

  def initialize(method:, method_name:, raw_arg_types:, raw_return_type:, bind:, mode:, check_level:, on_failure:, parameters: nil, override_allow_incompatible: false, defined_raw: false)
    check_level = check_level.nil? ? T::Private::RuntimeLevels.default_checked_level : check_level
    @method = method
    @method_name = method_name
    @block_type = nil
    @rest_type = nil
    @keyrest_type = nil
    @return_type = T::Utils.coerce(raw_return_type)
    @effective_return_type = if check_level == :tests && @return_type.is_a?(T::Private::Types::Void)
      T::Types::Anything::Private::INSTANCE
    else
      @return_type
    end
    @bind = NilClass.===(bind) ? bind : T::Utils.coerce(bind)
    @parameters = parameters
    parameters ||= method.parameters
    @on_failure = on_failure
    @flags = flag_index(FLAG_MODES, mode, 'mode') |
             (flag_index(FLAG_CHECK_LEVELS, check_level, 'check_level') << CHECK_LEVEL_SHIFT) |
             (flag_index(FLAG_ALLOW_INCOMPATIBLE, override_allow_incompatible, 'override_allow_incompatible') << ALLOW_INCOMPATIBLE_SHIFT) |
             (defined_raw ? DEFINED_RAW_BIT : 0)

    # Use T.untyped in lieu of T.nilable to try to avoid unnecessary allocations.
    arg_types = nil
    kwarg_types = nil
    req_kwarg_names = nil
    if T::Private::IS_TYPECHECKING
      arg_types = T.let(nil, T.nilable(T::Array[[Symbol, T::Types::Base]]))
      kwarg_types = T.let(nil, T.nilable(T::Hash[Symbol, T::Types::Base]))
      req_kwarg_names = T.let(nil, T.nilable(T::Array[Symbol]))
    end
    req_arg_count = 0

    # If sig params are declared but there is a single parameter with a missing name
    # **and** the method ends with a "=", assume it is a writer method generated
    # by attr_writer or attr_accessor
    # (Checks are ordered so that the common, non-writer case short-circuits without allocating.)
    writer_method = method_name.end_with?("=") && parameters == UNNAMED_REQUIRED_PARAMETERS && !(raw_arg_types.size == 1 && raw_arg_types.key?(nil))
    # For writer methods, map the single parameter to the method name without the "=" at the end
    parameters = [[:req, method_name[0...-1].to_sym]] if writer_method
    is_name_missing = parameters.any? { |_, name| !raw_arg_types.key?(name) }
    if is_name_missing
      param_names = parameters.map { |_, name| name }
      missing_names = param_names - raw_arg_types.keys
      raise "The declaration for `#{method.name}` is missing parameter(s): #{missing_names.join(', ')}"
    elsif parameters.length != raw_arg_types.size
      param_names = parameters.map { |_, name| name }
      has_extra_names = parameters.count { |_, name| raw_arg_types.key?(name) } < raw_arg_types.size
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
      param_kind, param_name = parameters.fetch(i)

      if type_name != param_name
        hint = ""
        # Ruby reorders params so that required keyword arguments
        # always precede optional keyword arguments. We can't tell
        # whether the culprit is the Ruby reordering or user error, so
        # we error but include a note
        if param_kind == :keyreq && parameters.any? { |k, _| k == :key }
          hint = "\n\nNote: Any required keyword arguments must precede any optional keyword " \
                 "arguments. If your method declaration matches your `def`, try reordering any " \
                 "optional keyword parameters to the end of the method list."
        end

        raise "Parameter `#{type_name}` is declared out of order (declared as arg number " \
              "#{i + 1}, defined in the method as arg number " \
              "#{T.must(parameters.index { |_, name| name == type_name }) + 1}).#{hint}\nMethod: #{method_desc}"
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
        @block_type = type
      when :rest
        @rest_type = type
      when :keyrest
        @keyrest_type = type
      else
        raise "Unexpected param_kind: `#{param_kind}`. Method: #{method_desc}"
      end

      i += 1
    end

    @parameters ||= parameters unless @rest_type.nil?
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

  # Names are derived rather than stored so that Signature fits in a smaller GC slot.
  def parameters
    @parameters || @method.parameters
  end

  def block_name
    parameter_name(:block)
  end

  def rest_name
    parameter_name(:rest)
  end

  def keyrest_name
    parameter_name(:keyrest)
  end

  def mode
    FLAG_MODES.fetch(@flags & MODE_MASK)
  end

  def check_level
    FLAG_CHECK_LEVELS.fetch((@flags >> CHECK_LEVEL_SHIFT) & CHECK_LEVEL_MASK)
  end

  def override_allow_incompatible
    FLAG_ALLOW_INCOMPATIBLE.fetch((@flags >> ALLOW_INCOMPATIBLE_SHIFT) & ALLOW_INCOMPATIBLE_MASK)
  end

  def defined_raw
    @flags.anybits?(DEFINED_RAW_BIT)
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
    if (args_length > @req_arg_count) && (!@kwarg_types.empty? || !@keyrest_type.nil?) && (last_arg = args[-1]).is_a?(Hash)
      kwargs = last_arg
      args_length -= 1
    else
      kwargs = EMPTY_HASH
    end

    if @rest_type.nil? && ((args_length < @req_arg_count) || (args_length > @arg_types.length))
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
        arg_type = @arg_types.fetch(it)
        yield arg_type[0], args[it], arg_type[1]
        it += 1
      end

      if !@rest_type.nil?
        rest_count = args_length - @arg_types.length

        if rest_count > 0
          rest_name = fast_rest_name

          rest_count.times do
            yield rest_name, args[it], @rest_type
            it += 1
          end
        end
      end
    end

    kwargs.each do |name, val|
      type = @kwarg_types[name]
      if !type && !@keyrest_type.nil?
        type = @keyrest_type
      end

      yield name, val, type if type
    end
  end

  def method_desc
    self.class.method_desc(@method, @method_name)
  end

  def self.method_desc(method, method_name, source_loc=method.source_location)
    loc = if source_loc
      source_loc.join(':')
    else
      "<unknown location>"
    end
    "#{method.owner}##{method_name} at #{loc}"
  end

  def force_type_init
    @arg_types.each { |_, type| type.build_type }
    @kwarg_types.each { |_, type| type.build_type }
    @block_type&.build_type
    @rest_type&.build_type
    @keyrest_type&.build_type
    @return_type.build_type
  end

  # The rest param directly follows the positional params unless required params come after it.
  private def fast_rest_name
    param_kind, param_name = parameters[@arg_types.length]
    param_kind == :rest ? param_name : parameter_name(:rest)
  end

  private def parameter_name(kind)
    parameters.assoc(kind)&.[](1)
  end

  private def flag_index(values, value, field)
    values.index(value) || raise(ArgumentError.new("Invalid #{field} for `#{@method_name}`: #{value.inspect}"))
  end

  EMPTY_LIST = [].freeze
  EMPTY_HASH = {}.freeze
end
