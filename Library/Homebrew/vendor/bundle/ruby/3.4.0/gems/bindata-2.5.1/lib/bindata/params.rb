require 'bindata/lazy'

module BinData
  module AcceptedParametersPlugin
    # Mandatory parameters must be present when instantiating a data object.
    def mandatory_parameters(*args)
      accepted_parameters.mandatory(*args)
    end

    # Optional parameters may be present when instantiating a data object.
    def optional_parameters(*args)
      accepted_parameters.optional(*args)
    end

    # Default parameters can be overridden when instantiating a data object.
    def default_parameters(*args)
      accepted_parameters.default(*args)
    end

    # Mutually exclusive parameters may not all be present when
    # instantiating a data object.
    def mutually_exclusive_parameters(*args)
      accepted_parameters.mutually_exclusive(*args)
    end

    alias mandatory_parameter mandatory_parameters
    alias optional_parameter  optional_parameters
    alias default_parameter   default_parameters

    def accepted_parameters # :nodoc:
      @accepted_parameters ||= begin
        ancestor_params = superclass.respond_to?(:accepted_parameters) ?
                            superclass.accepted_parameters : nil
        AcceptedParameters.new(ancestor_params)
      end
    end

    # BinData objects accept parameters when initializing.  AcceptedParameters
    # allow a BinData class to declaratively identify accepted parameters as
    # mandatory, optional, default or mutually exclusive.
    class AcceptedParameters
      def initialize(ancestor_parameters = nil)
        if ancestor_parameters
          @mandatory = ancestor_parameters.mandatory.dup
          @optional  = ancestor_parameters.optional.dup
          @default   = ancestor_parameters.default.dup
          @mutually_exclusive = ancestor_parameters.mutually_exclusive.dup
        else
          @mandatory = []
          @optional  = []
          @default   = Hash.new
          @mutually_exclusive = []
        end
      end

      def mandatory(*args)
        unless args.empty?
          @mandatory.concat(to_syms(args))
          @mandatory.uniq!
        end
        @mandatory
      end

      def optional(*args)
        unless args.empty?
          @optional.concat(to_syms(args))
          @optional.uniq!
        end
        @optional
      end

      def default(args = nil)
        if args
          to_syms(args.keys)  # call for side effect of validating names
          args.each_pair do |param, value|
            @default[param.to_sym] = value
          end
        end
        @default
      end

      def mutually_exclusive(*args)
        arg1 = args.shift
        until args.empty?
          args.each do |arg2|
            @mutually_exclusive.push([arg1.to_sym, arg2.to_sym])
            @mutually_exclusive.uniq!
          end
          arg1 = args.shift
        end
        @mutually_exclusive
      end

      def all
        (@mandatory + @optional + @default.keys).uniq
      end

      #---------------
      private

      def to_syms(args)
        syms = args.collect(&:to_sym)
        ensure_valid_names(syms)
        syms
      end

      def ensure_valid_names(names)
        invalid_names = self.class.invalid_parameter_names
        names.each do |name|
          if invalid_names.include?(name)
            raise NameError.new("Rename parameter '#{name}' " \
                                "as it shadows an existing method.", name)
          end
        end
      end

      class << self
        def invalid_parameter_names
          @invalid_parameter_names ||= begin
            all_names = LazyEvaluator.instance_methods(true)
            allowed_names = [:name, :type]
            invalid_names = (all_names - allowed_names).uniq

            Hash[*invalid_names.collect { |key| [key.to_sym, true] }.flatten]
          end
        end
      end
    end
  end
end
