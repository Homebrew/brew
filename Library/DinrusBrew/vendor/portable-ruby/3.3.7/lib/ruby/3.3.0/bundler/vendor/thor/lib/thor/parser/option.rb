class Bundler::Thor
  class Option < Argument #:nodoc:
    attr_reader :aliases, :group, :lazy_default, :hide, :repeatable

    VALID_TYPES = [:boolean, :numeric, :hash, :array, :string]

    def initialize(name, options = {})
      @check_default_type = options[:check_default_type]
      options[:required] = false unless options.key?(:required)
      @repeatable     = options.fetch(:repeatable, false)
      super
      @lazy_default   = options[:lazy_default]
      @group          = options[:group].to_s.capitalize if options[:group]
      @aliases        = normalize_aliases(options[:aliases])
      @hide           = options[:hide]
    end

    # This parse quick options given as method_options. It makes several
    # assumptions, but you can be more specific using the option method.
    #
    #   parse :foo => "bar"
    #   #=> Option foo with default value bar
    #
    #   parse [:foo, :baz] => "bar"
    #   #=> Option foo with default value bar and alias :baz
    #
    #   parse :foo => :required
    #   #=> Required option foo without default value
    #
    #   parse :foo => 2
    #   #=> Option foo with default value 2 and type numeric
    #
    #   parse :foo => :numeric
    #   #=> Option foo without default value and type numeric
    #
    #   parse :foo => true
    #   #=> Option foo with default value true and type boolean
    #
    # The valid types are :boolean, :numeric, :hash, :array and :string. If none
    # is given a default type is assumed. This default type accepts arguments as
    # string (--foo=value) or booleans (just --foo).
    #
    # By default all options are optional, unless :required is given.
    #
    def self.parse(key, value)
      if key.is_a?(Array)
        name, *aliases = key
      else
        name = key
        aliases = []
      end

      name    = name.to_s
      default = value

      type = case value
      when Symbol
        default = nil
        if VALID_TYPES.include?(value)
          value
        elsif required = (value == :required) # rubocop:disable Lint/AssignmentInCondition
          :string
        end
      when TrueClass, FalseClass
        :boolean
      when Numeric
        :numeric
      when Hash, Array, String
        value.class.name.downcase.to_sym
      end

      new(name.to_s, required: required, type: type, default: default, aliases: aliases)
    end

    def switch_name
      @switch_name ||= dasherized? ? name : dasherize(name)
    end

    def human_name
      @human_name ||= dasherized? ? undasherize(name) : name
    end

    def usage(padding = 0)
      sample = if banner && !banner.to_s.empty?
        "#{switch_name}=#{banner}".dup
      else
        switch_name
      end

      sample = "[#{sample}]".dup unless required?

      if boolean?
        sample << ", [#{dasherize('no-' + human_name)}]" unless (name == "force") || name.match(/\Ano[\-_]/)
      end

      aliases_for_usage.ljust(padding) + sample
    end

    def aliases_for_usage
      if aliases.empty?
        ""
      else
        "#{aliases.join(', ')}, "
      end
    end

    def show_default?
      case default
      when TrueClass, FalseClass
        true
      else
        super
      end
    end

    VALID_TYPES.each do |type|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{type}?
          self.type == #{type.inspect}
        end
      RUBY
    end

  protected

    def validate!
      raise ArgumentError, "An option cannot be boolean and required." if boolean? && required?
      validate_default_type!
    end

    def validate_default_type!
      default_type = case @default
      when nil
        return
      when TrueClass, FalseClass
        required? ? :string : :boolean
      when Numeric
        :numeric
      when Symbol
        :string
      when Hash, Array, String
        @default.class.name.downcase.to_sym
      end

      expected_type = (@repeatable && @type != :hash) ? :array : @type

      if default_type != expected_type
        err = "Expected #{expected_type} default value for '#{switch_name}'; got #{@default.inspect} (#{default_type})"

        if @check_default_type
          raise ArgumentError, err
        elsif @check_default_type == nil
          Bundler::Thor.deprecation_warning "#{err}.\n" +
            "This will be rejected in the future unless you explicitly pass the options `check_default_type: false`" +
            " or call `allow_incompatible_default_type!` in your code"
        end
      end
    end

    def dasherized?
      name.index("-") == 0
    end

    def undasherize(str)
      str.sub(/^-{1,2}/, "")
    end

    def dasherize(str)
      (str.length > 1 ? "--" : "-") + str.tr("_", "-")
    end

  private

    def normalize_aliases(aliases)
      Array(aliases).map { |short| short.to_s.sub(/^(?!\-)/, "-") }
    end
  end
end
