class Bundler::Thor
  class Arguments #:nodoc:
    NUMERIC = /[-+]?(\d*\.\d+|\d+)/

    # Receives an array of args and returns two arrays, one with arguments
    # and one with switches.
    #
    def self.split(args)
      arguments = []

      args.each do |item|
        break if item.is_a?(String) && item =~ /^-/
        arguments << item
      end

      [arguments, args[Range.new(arguments.size, -1)]]
    end

    def self.parse(*args)
      to_parse = args.pop
      new(*args).parse(to_parse)
    end

    # Takes an array of Bundler::Thor::Argument objects.
    #
    def initialize(arguments = [])
      @assigns = {}
      @non_assigned_required = []
      @switches = arguments

      arguments.each do |argument|
        if !argument.default.nil?
          @assigns[argument.human_name] = argument.default.dup
        elsif argument.required?
          @non_assigned_required << argument
        end
      end
    end

    def parse(args)
      @pile = args.dup

      @switches.each do |argument|
        break unless peek
        @non_assigned_required.delete(argument)
        @assigns[argument.human_name] = send(:"parse_#{argument.type}", argument.human_name)
      end

      check_requirement!
      @assigns
    end

    def remaining
      @pile
    end

  private

    def no_or_skip?(arg)
      arg =~ /^--(no|skip)-([-\w]+)$/
      $2
    end

    def last?
      @pile.empty?
    end

    def peek
      @pile.first
    end

    def shift
      @pile.shift
    end

    def unshift(arg)
      if arg.is_a?(Array)
        @pile = arg + @pile
      else
        @pile.unshift(arg)
      end
    end

    def current_is_value?
      peek && peek.to_s !~ /^-{1,2}\S+/
    end

    # Runs through the argument array getting strings that contains ":" and
    # mark it as a hash:
    #
    #   [ "name:string", "age:integer" ]
    #
    # Becomes:
    #
    #   { "name" => "string", "age" => "integer" }
    #
    def parse_hash(name)
      return shift if peek.is_a?(Hash)
      hash = {}

      while current_is_value? && peek.include?(":")
        key, value = shift.split(":", 2)
        raise MalformattedArgumentError, "You can't specify '#{key}' more than once in option '#{name}'; got #{key}:#{hash[key]} and #{key}:#{value}" if hash.include? key
        hash[key] = value
      end
      hash
    end

    # Runs through the argument array getting all strings until no string is
    # found or a switch is found.
    #
    #   ["a", "b", "c"]
    #
    # And returns it as an array:
    #
    #   ["a", "b", "c"]
    #
    def parse_array(name)
      return shift if peek.is_a?(Array)

      array = []

      while current_is_value?
        value = shift

        if !value.empty?
          validate_enum_value!(name, value, "Expected all values of '%s' to be one of %s; got %s")
        end

        array << value
      end
      array
    end

    # Check if the peek is numeric format and return a Float or Integer.
    # Check if the peek is included in enum if enum is provided.
    # Otherwise raises an error.
    #
    def parse_numeric(name)
      return shift if peek.is_a?(Numeric)

      unless peek =~ NUMERIC && $& == peek
        raise MalformattedArgumentError, "Expected numeric value for '#{name}'; got #{peek.inspect}"
      end

      value = $&.index(".") ? shift.to_f : shift.to_i

      validate_enum_value!(name, value, "Expected '%s' to be one of %s; got %s")

      value
    end

    # Parse string:
    # for --string-arg, just return the current value in the pile
    # for --no-string-arg, nil
    # Check if the peek is included in enum if enum is provided. Otherwise raises an error.
    #
    def parse_string(name)
      if no_or_skip?(name)
        nil
      else
        value = shift

        validate_enum_value!(name, value, "Expected '%s' to be one of %s; got %s")

        value
      end
    end

    # Raises an error if the switch is an enum and the values aren't included on it.
    #
    def validate_enum_value!(name, value, message)
      return unless @switches.is_a?(Hash)

      switch = @switches[name]

      return unless switch

      if switch.enum && !switch.enum.include?(value)
        raise MalformattedArgumentError, message % [name, switch.enum_to_s, value]
      end
    end

    # Raises an error if @non_assigned_required array is not empty.
    #
    def check_requirement!
      return if @non_assigned_required.empty?
      names = @non_assigned_required.map do |o|
        o.respond_to?(:switch_name) ? o.switch_name : o.human_name
      end.join("', '")
      class_name = self.class.name.split("::").last.downcase
      raise RequiredArgumentMissingError, "No value provided for required #{class_name} '#{names}'"
    end
  end
end
