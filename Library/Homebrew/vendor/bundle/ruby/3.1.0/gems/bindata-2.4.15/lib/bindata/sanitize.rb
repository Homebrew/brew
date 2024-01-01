require 'bindata/registry'

module BinData

  # Subclasses of this are sanitized
  class SanitizedParameter; end

  class SanitizedPrototype < SanitizedParameter
    def initialize(obj_type, obj_params, hints)
      raw_hints = hints.dup
      if raw_hints[:endian].respond_to?(:endian)
        raw_hints[:endian] = raw_hints[:endian].endian
      end
      obj_params ||= {}

      if BinData::Base === obj_type
        obj_class = obj_type
      else
        obj_class = RegisteredClasses.lookup(obj_type, raw_hints)
      end

      if BinData::Base === obj_class
        @factory = obj_class
      else
        @obj_class  = obj_class
        @obj_params = SanitizedParameters.new(obj_params, @obj_class, hints)
      end
    end

    def has_parameter?(param)
      if defined? @factory
        @factory.has_parameter?(param)
      else
        @obj_params.has_parameter?(param)
      end
    end

    def instantiate(value = nil, parent = nil)
      @factory ||= @obj_class.new(@obj_params)

      @factory.new(value, parent)
    end
  end
  #----------------------------------------------------------------------------

  class SanitizedField < SanitizedParameter
    def initialize(name, field_type, field_params, hints)
      @name      = name
      @prototype = SanitizedPrototype.new(field_type, field_params, hints)
    end

    attr_reader :prototype

    def name_as_sym
      @name.nil? ? nil : @name.to_sym
    end

    def name
      @name
    end

    def has_parameter?(param)
      @prototype.has_parameter?(param)
    end

    def instantiate(value = nil, parent = nil)
      @prototype.instantiate(value, parent)
    end
  end
  #----------------------------------------------------------------------------

  class SanitizedFields < SanitizedParameter
    include Enumerable

    def initialize(hints, base_fields = nil)
      @hints = hints
      if base_fields
        @fields = base_fields.raw_fields
      else
        @fields = []
      end
    end

    def add_field(type, name, params)
      name = nil if name == ""

      @fields << SanitizedField.new(name, type, params, @hints)
    end

    def raw_fields
      @fields.dup
    end

    def [](idx)
      @fields[idx]
    end

    def empty?
      @fields.empty?
    end

    def length
      @fields.length
    end

    def each(&block)
      @fields.each(&block)
    end

    def field_names
      @fields.collect(&:name_as_sym)
    end

    def field_name?(name)
      @fields.detect { |f| f.name_as_sym == name.to_sym }
    end

    def all_field_names_blank?
      @fields.all? { |f| f.name.nil? }
    end

    def no_field_names_blank?
      @fields.all? { |f| f.name != nil }
    end

    def any_field_has_parameter?(parameter)
      @fields.any? { |f| f.has_parameter?(parameter) }
    end
  end
  #----------------------------------------------------------------------------

  class SanitizedChoices < SanitizedParameter
    def initialize(choices, hints)
      @choices = {}
      choices.each_pair do |key, val|
        if SanitizedParameter === val
          prototype = val
        else
          type, param = val
          prototype = SanitizedPrototype.new(type, param, hints)
        end

        if key == :default
          @choices.default = prototype
        else
          @choices[key] = prototype
        end
      end
    end

    def [](key)
      @choices[key]
    end
  end
  #----------------------------------------------------------------------------

  class SanitizedBigEndian < SanitizedParameter
    def endian
      :big
    end
  end

  class SanitizedLittleEndian < SanitizedParameter
    def endian
      :little
    end
  end
  #----------------------------------------------------------------------------

  # BinData objects are instantiated with parameters to determine their
  # behaviour.  These parameters must be sanitized to ensure their values
  # are valid.  When instantiating many objects with identical parameters,
  # such as an array of records, there is much duplicated sanitizing.
  #
  # The purpose of the sanitizing code is to eliminate the duplicated
  # validation.
  #
  # SanitizedParameters is a hash-like collection of parameters.  Its purpose
  # is to recursively sanitize the parameters of an entire BinData object chain
  # at a single time.
  class SanitizedParameters < Hash

    # Memoized constants
    BIG_ENDIAN    = SanitizedBigEndian.new
    LITTLE_ENDIAN = SanitizedLittleEndian.new

    class << self
      def sanitize(parameters, the_class)
        if SanitizedParameters === parameters
          parameters
        else
          SanitizedParameters.new(parameters, the_class, {})
        end
      end
    end

    def initialize(parameters, the_class, hints)
      parameters.each_pair { |key, value| self[key.to_sym] = value }

      @the_class = the_class

      if hints[:endian]
        self[:endian] ||= hints[:endian]
      end

      if hints[:search_prefix] && !hints[:search_prefix].empty?
        self[:search_prefix] = Array(self[:search_prefix]).concat(Array(hints[:search_prefix]))
      end

      sanitize!
    end

    alias_method :has_parameter?, :key?

    def has_at_least_one_of?(*keys)
      keys.each do |key|
        return true if has_parameter?(key)
      end

      false
    end

    def warn_replacement_parameter(bad_key, suggested_key)
      if has_parameter?(bad_key)
        Kernel.warn ":#{bad_key} is not used with #{@the_class}.  " \
                    "You probably want to change this to :#{suggested_key}"
      end
    end

#    def warn_renamed_parameter(old_key, new_key)
#      val = delete(old_key)
#      if val
#        self[new_key] = val
#        Kernel.warn ":#{old_key} has been renamed to :#{new_key} in #{@the_class}.  " \
#        "Using :#{old_key} is now deprecated and will be removed in the future"
#      end
#    end

    def must_be_integer(*keys)
      keys.each do |key|
        if has_parameter?(key)
          parameter = self[key]
          unless Symbol === parameter ||
                 parameter.respond_to?(:arity) ||
                 parameter.respond_to?(:to_int)
            raise ArgumentError, "parameter '#{key}' in #{@the_class} must " \
                                 "evaluate to an integer, got #{parameter.class}"
          end
        end
      end
    end

    def rename_parameter(old_key, new_key)
      if has_parameter?(old_key)
        self[new_key] = delete(old_key)
      end
    end

    def sanitize_object_prototype(key)
      sanitize(key) { |obj_type, obj_params| create_sanitized_object_prototype(obj_type, obj_params) }
    end

    def sanitize_fields(key, &block)
      sanitize(key) do |fields|
        sanitized_fields = create_sanitized_fields
        yield(fields, sanitized_fields)
        sanitized_fields
      end
    end

    def sanitize_choices(key, &block)
      sanitize(key) do |obj|
        create_sanitized_choices(yield(obj))
      end
    end

    def sanitize_endian(key)
      sanitize(key) { |endian| create_sanitized_endian(endian) }
    end

    def sanitize(key, &block)
      if needs_sanitizing?(key)
        self[key] = yield(self[key])
      end
    end

    def create_sanitized_params(params, the_class)
      SanitizedParameters.new(params, the_class, hints)
    end

    def hints
      { endian: self[:endian], search_prefix: self[:search_prefix] }
    end

    #---------------
    private

    def sanitize!
      ensure_no_nil_values
      merge_default_parameters!

      @the_class.arg_processor.sanitize_parameters!(@the_class, self)

      ensure_mandatory_parameters_exist
      ensure_mutual_exclusion_of_parameters
    end

    def needs_sanitizing?(key)
      has_key?(key) && ! self[key].is_a?(SanitizedParameter)
    end

    def ensure_no_nil_values
      each do |key, value|
        if value.nil?
          raise ArgumentError,
                "parameter '#{key}' has nil value in #{@the_class}"
        end
      end
    end

    def merge_default_parameters!
      @the_class.default_parameters.each do |key, value|
        self[key] = value unless has_key?(key)
      end
    end

    def ensure_mandatory_parameters_exist
      @the_class.mandatory_parameters.each do |key|
        unless has_parameter?(key)
          raise ArgumentError,
                  "parameter '#{key}' must be specified in #{@the_class}"
        end
      end
    end

    def ensure_mutual_exclusion_of_parameters
      return if length < 2

      @the_class.mutually_exclusive_parameters.each do |key1, key2|
        if has_parameter?(key1) && has_parameter?(key2)
          raise ArgumentError, "params '#{key1}' and '#{key2}' " \
                               "are mutually exclusive in #{@the_class}"
        end
      end
    end

    def create_sanitized_endian(endian)
      if endian == :big
        BIG_ENDIAN
      elsif endian == :little
        LITTLE_ENDIAN
      elsif endian == :big_and_little
        raise ArgumentError, "endian: :big or endian: :little is required"
      else
        raise ArgumentError, "unknown value for endian '#{endian}'"
      end
    end

    def create_sanitized_choices(choices)
      SanitizedChoices.new(choices, hints)
    end

    def create_sanitized_fields
      SanitizedFields.new(hints)
    end

    def create_sanitized_object_prototype(obj_type, obj_params)
      SanitizedPrototype.new(obj_type, obj_params, hints)
    end
  end
  #----------------------------------------------------------------------------
end
