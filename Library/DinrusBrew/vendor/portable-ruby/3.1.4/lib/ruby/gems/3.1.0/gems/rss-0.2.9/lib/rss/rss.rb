# frozen_string_literal: false
require "time"

class Time
  class << self
    unless respond_to?(:w3cdtf)
      # This method converts a W3CDTF string date/time format to Time object.
      #
      # The W3CDTF format is defined here: http://www.w3.org/TR/NOTE-datetime
      #
      #   Time.w3cdtf('2003-02-15T13:50:05-05:00')
      #   # => 2003-02-15 10:50:05 -0800
      #   Time.w3cdtf('2003-02-15T13:50:05-05:00').class
      #   # => Time
      def w3cdtf(date)
        if /\A\s*
            (-?\d+)-(\d\d)-(\d\d)
            (?:T
            (\d\d):(\d\d)(?::(\d\d))?
            (\.\d+)?
            (Z|[+-]\d\d:\d\d)?)?
            \s*\z/ix =~ date and (($5 and $8) or (!$5 and !$8))
          datetime = [$1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i]
          usec = 0
          usec = $7.to_f * 1000000 if $7
          zone = $8
          if zone
            off = zone_offset(zone, datetime[0])
            datetime = apply_offset(*(datetime + [off]))
            datetime << usec
            time = Time.utc(*datetime)
            force_zone!(time, zone, off)
            time
          else
            datetime << usec
            Time.local(*datetime)
          end
        else
          raise ArgumentError.new("invalid date: #{date.inspect}")
        end
      end
    end
  end

  unless method_defined?(:w3cdtf)
    # This method converts a Time object to a String. The String contains the
    # time in W3CDTF date/time format.
    #
    # The W3CDTF format is defined here: http://www.w3.org/TR/NOTE-datetime
    #
    #  Time.now.w3cdtf
    #  # => "2013-08-26T14:12:10.817124-07:00"
    def w3cdtf
      if usec.zero?
        fraction_digits = 0
      else
        fraction_digits = strftime('%6N').index(/0*\z/)
      end
      xmlschema(fraction_digits)
    end
  end
end


require "English"
require_relative "utils"
require_relative "converter"
require_relative "xml-stylesheet"

module RSS
  # The URI of the RSS 1.0 specification
  URI = "http://purl.org/rss/1.0/"

  DEBUG = false # :nodoc:

  # The basic error all other RSS errors stem from. Rescue this error if you
  # want to handle any given RSS error and you don't care about the details.
  class Error < StandardError; end

  # RSS, being an XML-based format, has namespace support. If two namespaces are
  # declared with the same name, an OverlappedPrefixError will be raised.
  class OverlappedPrefixError < Error
    attr_reader :prefix
    def initialize(prefix)
      @prefix = prefix
    end
  end

  # The InvalidRSSError error is the base class for a variety of errors
  # related to a poorly-formed RSS feed. Rescue this error if you only
  # care that a file could be invalid, but don't care how it is invalid.
  class InvalidRSSError < Error; end

  # Since RSS is based on XML, it must have opening and closing tags that
  # match. If they don't, a MissingTagError will be raised.
  class MissingTagError < InvalidRSSError
    attr_reader :tag, :parent
    def initialize(tag, parent)
      @tag, @parent = tag, parent
      super("tag <#{tag}> is missing in tag <#{parent}>")
    end
  end

  # Some tags must only exist a specific number of times in a given RSS feed.
  # If a feed has too many occurrences of one of these tags, a TooMuchTagError
  # will be raised.
  class TooMuchTagError < InvalidRSSError
    attr_reader :tag, :parent
    def initialize(tag, parent)
      @tag, @parent = tag, parent
      super("tag <#{tag}> is too much in tag <#{parent}>")
    end
  end

  # Certain attributes are required on specific tags in an RSS feed. If a feed
  # is missing one of these attributes, a MissingAttributeError is raised.
  class MissingAttributeError < InvalidRSSError
    attr_reader :tag, :attribute
    def initialize(tag, attribute)
      @tag, @attribute = tag, attribute
      super("attribute <#{attribute}> is missing in tag <#{tag}>")
    end
  end

  # RSS does not allow for free-form tag names, so if an RSS feed contains a
  # tag that we don't know about, an UnknownTagError is raised.
  class UnknownTagError < InvalidRSSError
    attr_reader :tag, :uri
    def initialize(tag, uri)
      @tag, @uri = tag, uri
      super("tag <#{tag}> is unknown in namespace specified by uri <#{uri}>")
    end
  end

  # Raised when an unexpected tag is encountered.
  class NotExpectedTagError < InvalidRSSError
    attr_reader :tag, :uri, :parent
    def initialize(tag, uri, parent)
      @tag, @uri, @parent = tag, uri, parent
      super("tag <{#{uri}}#{tag}> is not expected in tag <#{parent}>")
    end
  end
  # For backward compatibility :X
  NotExceptedTagError = NotExpectedTagError # :nodoc:

  # Attributes are in key-value form, and if there's no value provided for an
  # attribute, a NotAvailableValueError will be raised.
  class NotAvailableValueError < InvalidRSSError
    attr_reader :tag, :value, :attribute
    def initialize(tag, value, attribute=nil)
      @tag, @value, @attribute = tag, value, attribute
      message = "value <#{value}> of "
      message << "attribute <#{attribute}> of " if attribute
      message << "tag <#{tag}> is not available."
      super(message)
    end
  end

  # Raised when an unknown conversion error occurs.
  class UnknownConversionMethodError < Error
    attr_reader :to, :from
    def initialize(to, from)
      @to = to
      @from = from
      super("can't convert to #{to} from #{from}.")
    end
  end
  # for backward compatibility
  UnknownConvertMethod = UnknownConversionMethodError # :nodoc:

  # Raised when a conversion failure occurs.
  class ConversionError < Error
    attr_reader :string, :to, :from
    def initialize(string, to, from)
      @string = string
      @to = to
      @from = from
      super("can't convert #{@string} to #{to} from #{from}.")
    end
  end

  # Raised when a required variable is not set.
  class NotSetError < Error
    attr_reader :name, :variables
    def initialize(name, variables)
      @name = name
      @variables = variables
      super("required variables of #{@name} are not set: #{@variables.join(', ')}")
    end
  end

  # Raised when a RSS::Maker attempts to use an unknown maker.
  class UnsupportedMakerVersionError < Error
    attr_reader :version
    def initialize(version)
      @version = version
      super("Maker doesn't support version: #{@version}")
    end
  end

  module BaseModel
    include Utils

    def install_have_child_element(tag_name, uri, occurs, name=nil, type=nil)
      name ||= tag_name
      add_need_initialize_variable(name)
      install_model(tag_name, uri, occurs, name)

      writer_type, reader_type = type
      def_corresponded_attr_writer name, writer_type
      def_corresponded_attr_reader name, reader_type
      install_element(name) do |n, elem_name|
        <<-EOC
        if @#{n}
          "\#{@#{n}.to_s(need_convert, indent)}"
        else
          ''
        end
EOC
      end
    end
    alias_method(:install_have_attribute_element, :install_have_child_element)

    def install_have_children_element(tag_name, uri, occurs, name=nil, plural_name=nil)
      name ||= tag_name
      plural_name ||= "#{name}s"
      add_have_children_element(name, plural_name)
      add_plural_form(name, plural_name)
      install_model(tag_name, uri, occurs, plural_name, true)

      def_children_accessor(name, plural_name)
      install_element(name, "s") do |n, elem_name|
        <<-EOC
        rv = []
        @#{n}.each do |x|
          value = "\#{x.to_s(need_convert, indent)}"
          rv << value if /\\A\\s*\\z/ !~ value
        end
        rv.join("\n")
EOC
      end
    end

    def install_text_element(tag_name, uri, occurs, name=nil, type=nil,
                             disp_name=nil)
      name ||= tag_name
      disp_name ||= name
      self::ELEMENTS << name unless self::ELEMENTS.include?(name)
      add_need_initialize_variable(name)
      install_model(tag_name, uri, occurs, name)

      def_corresponded_attr_writer(name, type, disp_name)
      def_corresponded_attr_reader(name, type || :convert)
      install_element(name) do |n, elem_name|
        <<-EOC
        if respond_to?(:#{n}_content)
          content = #{n}_content
        else
          content = @#{n}
        end
        if content
          rv = "\#{indent}<#{elem_name}>"
          value = html_escape(content)
          if need_convert
            rv << convert(value)
          else
            rv << value
          end
            rv << "</#{elem_name}>"
          rv
        else
          ''
        end
EOC
      end
    end

    def install_date_element(tag_name, uri, occurs, name=nil, type=nil, disp_name=nil)
      name ||= tag_name
      type ||= :w3cdtf
      disp_name ||= name
      self::ELEMENTS << name
      add_need_initialize_variable(name)
      install_model(tag_name, uri, occurs, name)

      # accessor
      convert_attr_reader name
      date_writer(name, type, disp_name)

      install_element(name) do |n, elem_name|
        <<-EOC
        if @#{n}
          rv = "\#{indent}<#{elem_name}>"
          value = html_escape(@#{n}.#{type})
          if need_convert
            rv << convert(value)
          else
            rv << value
          end
            rv << "</#{elem_name}>"
          rv
        else
          ''
        end
EOC
      end

    end

    private
    def install_element(name, postfix="")
      elem_name = name.sub('_', ':')
      method_name = "#{name}_element#{postfix}"
      add_to_element_method(method_name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{method_name}(need_convert=true, indent='')
        #{yield(name, elem_name)}
      end
      private :#{method_name}
EOC
    end

    def inherit_convert_attr_reader(*attrs)
      attrs.each do |attr|
        module_eval(<<-EOC, *get_file_and_line_from_caller(2))
        def #{attr}_without_inherit
          convert(@#{attr})
        end

        def #{attr}
          if @#{attr}
            #{attr}_without_inherit
          elsif @parent
            @parent.#{attr}
          else
            nil
          end
        end
EOC
      end
    end

    def uri_convert_attr_reader(*attrs)
      attrs.each do |attr|
        module_eval(<<-EOC, *get_file_and_line_from_caller(2))
        def #{attr}_without_base
          convert(@#{attr})
        end

        def #{attr}
          value = #{attr}_without_base
          return nil if value.nil?
          if /\\A[a-z][a-z0-9+.\\-]*:/i =~ value
            value
          else
            "\#{base}\#{value}"
          end
        end
EOC
      end
    end

    def convert_attr_reader(*attrs)
      attrs.each do |attr|
        module_eval(<<-EOC, *get_file_and_line_from_caller(2))
        def #{attr}
          convert(@#{attr})
        end
EOC
      end
    end

    def explicit_clean_other_attr_reader(*attrs)
      attrs.each do |attr|
        module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_reader(:#{attr})
          def #{attr}?
            ExplicitCleanOther.parse(@#{attr})
          end
        EOC
      end
    end

    def yes_other_attr_reader(*attrs)
      attrs.each do |attr|
        module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_reader(:#{attr})
          def #{attr}?
            Utils::YesOther.parse(@#{attr})
          end
        EOC
      end
    end

    def csv_attr_reader(*attrs)
      separator = nil
      if attrs.last.is_a?(Hash)
        options = attrs.pop
        separator = options[:separator]
      end
      separator ||= ", "
      attrs.each do |attr|
        module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          attr_reader(:#{attr})
          def #{attr}_content
            if @#{attr}.nil?
              @#{attr}
            else
              @#{attr}.join(#{separator.dump})
            end
          end
        EOC
      end
    end

    def date_writer(name, type, disp_name=name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.nil?
          @#{name} = new_value
        elsif new_value.kind_of?(Time)
          @#{name} = new_value.dup
        else
          if @do_validate
            begin
              @#{name} = Time.__send__('#{type}', new_value)
            rescue ArgumentError
              raise NotAvailableValueError.new('#{disp_name}', new_value)
            end
          else
            @#{name} = nil
            if /\\A\\s*\\z/ !~ new_value.to_s
              begin
                unless Date._parse(new_value, false).empty?
                  @#{name} = Time.parse(new_value)
                end
              rescue ArgumentError
              end
            end
          end
        end

        # Is it need?
        if @#{name}
          class << @#{name}
            undef_method(:to_s)
            alias_method(:to_s, :#{type})
          end
        end

      end
EOC
    end

    def integer_writer(name, disp_name=name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.nil?
          @#{name} = new_value
        else
          if @do_validate
            begin
              @#{name} = Integer(new_value)
            rescue ArgumentError
              raise NotAvailableValueError.new('#{disp_name}', new_value)
            end
          else
            @#{name} = new_value.to_i
          end
        end
      end
EOC
    end

    def positive_integer_writer(name, disp_name=name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.nil?
          @#{name} = new_value
        else
          if @do_validate
            begin
              tmp = Integer(new_value)
              raise ArgumentError if tmp <= 0
              @#{name} = tmp
            rescue ArgumentError
              raise NotAvailableValueError.new('#{disp_name}', new_value)
            end
          else
            @#{name} = new_value.to_i
          end
        end
      end
EOC
    end

    def boolean_writer(name, disp_name=name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.nil?
          @#{name} = new_value
        else
          if @do_validate and
              ![true, false, "true", "false"].include?(new_value)
            raise NotAvailableValueError.new('#{disp_name}', new_value)
          end
          if [true, false].include?(new_value)
            @#{name} = new_value
          else
            @#{name} = new_value == "true"
          end
        end
      end
EOC
    end

    def text_type_writer(name, disp_name=name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if @do_validate and
            !["text", "html", "xhtml", nil].include?(new_value)
          raise NotAvailableValueError.new('#{disp_name}', new_value)
        end
        @#{name} = new_value
      end
EOC
    end

    def content_writer(name, disp_name=name)
      klass_name = "self.class::#{Utils.to_class_name(name)}"
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{name}=(new_value)
        if new_value.is_a?(#{klass_name})
          @#{name} = new_value
        else
          @#{name} = #{klass_name}.new
          @#{name}.content = new_value
        end
      end
EOC
    end

    def explicit_clean_other_writer(name, disp_name=name)
      module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        def #{name}=(value)
          value = (value ? "yes" : "no") if [true, false].include?(value)
          @#{name} = value
        end
      EOC
    end

    def yes_other_writer(name, disp_name=name)
      module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        def #{name}=(new_value)
          if [true, false].include?(new_value)
            new_value = new_value ? "yes" : "no"
          end
          @#{name} = new_value
        end
      EOC
    end

    def csv_writer(name, disp_name=name)
      module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        def #{name}=(new_value)
          @#{name} = Utils::CSV.parse(new_value)
        end
      EOC
    end

    def csv_integer_writer(name, disp_name=name)
      module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        def #{name}=(new_value)
          @#{name} = Utils::CSV.parse(new_value) {|v| Integer(v)}
        end
      EOC
    end

    def def_children_accessor(accessor_name, plural_name)
      module_eval(<<-EOC, *get_file_and_line_from_caller(2))
      def #{plural_name}
        @#{accessor_name}
      end

      def #{accessor_name}(*args)
        if args.empty?
          @#{accessor_name}.first
        else
          @#{accessor_name}[*args]
        end
      end

      def #{accessor_name}=(*args)
        receiver = self.class.name
        warn("Don't use `\#{receiver}\##{accessor_name} = XXX'/" \
             "`\#{receiver}\#set_#{accessor_name}(XXX)'. " \
             "Those APIs are not sense of Ruby. " \
             "Use `\#{receiver}\##{plural_name} << XXX' instead of them.", uplevel: 1)
        if args.size == 1
          @#{accessor_name}.push(args[0])
        else
          @#{accessor_name}.__send__("[]=", *args)
        end
      end
      alias_method(:set_#{accessor_name}, :#{accessor_name}=)
EOC
    end
  end

  module SetupMaker
    def setup_maker(maker)
      target = maker_target(maker)
      unless target.nil?
        setup_maker_attributes(target)
        setup_maker_element(target)
        setup_maker_elements(target)
      end
    end

    private
    def maker_target(maker)
      nil
    end

    def setup_maker_attributes(target)
    end

    def setup_maker_element(target)
      self.class.need_initialize_variables.each do |var|
        value = __send__(var)
        next if value.nil?
        if value.respond_to?("setup_maker") and
            !not_need_to_call_setup_maker_variables.include?(var)
          value.setup_maker(target)
        else
          setter = "#{var}="
          if target.respond_to?(setter)
            target.__send__(setter, value)
          end
        end
      end
    end

    def not_need_to_call_setup_maker_variables
      []
    end

    def setup_maker_elements(parent)
      self.class.have_children_elements.each do |name, plural_name|
        if parent.respond_to?(plural_name)
          target = parent.__send__(plural_name)
          __send__(plural_name).each do |elem|
            elem.setup_maker(target)
          end
        end
      end
    end
  end

  class Element
    extend BaseModel
    include Utils
    extend Utils::InheritedReader
    include SetupMaker

    INDENT = "  "

    MUST_CALL_VALIDATORS = {}
    MODELS = []
    GET_ATTRIBUTES = []
    HAVE_CHILDREN_ELEMENTS = []
    TO_ELEMENT_METHODS = []
    NEED_INITIALIZE_VARIABLES = []
    PLURAL_FORMS = {}

    class << self
      def must_call_validators
        inherited_hash_reader("MUST_CALL_VALIDATORS")
      end
      def models
        inherited_array_reader("MODELS")
      end
      def get_attributes
        inherited_array_reader("GET_ATTRIBUTES")
      end
      def have_children_elements
        inherited_array_reader("HAVE_CHILDREN_ELEMENTS")
      end
      def to_element_methods
        inherited_array_reader("TO_ELEMENT_METHODS")
      end
      def need_initialize_variables
        inherited_array_reader("NEED_INITIALIZE_VARIABLES")
      end
      def plural_forms
        inherited_hash_reader("PLURAL_FORMS")
      end

      def inherited_base
        ::RSS::Element
      end

      def inherited(klass)
        klass.const_set(:MUST_CALL_VALIDATORS, {})
        klass.const_set(:MODELS, [])
        klass.const_set(:GET_ATTRIBUTES, [])
        klass.const_set(:HAVE_CHILDREN_ELEMENTS, [])
        klass.const_set(:TO_ELEMENT_METHODS, [])
        klass.const_set(:NEED_INITIALIZE_VARIABLES, [])
        klass.const_set(:PLURAL_FORMS, {})

        tag_name = klass.name.split(/::/).last
        tag_name[0, 1] = tag_name[0, 1].downcase
        klass.instance_variable_set(:@tag_name, tag_name)
        klass.instance_variable_set(:@have_content, false)
      end

      def install_must_call_validator(prefix, uri)
        self::MUST_CALL_VALIDATORS[uri] = prefix
      end

      def install_model(tag, uri, occurs=nil, getter=nil, plural=false)
        getter ||= tag
        if m = self::MODELS.find {|t, u, o, g, p| t == tag and u == uri}
          m[2] = occurs
        else
          self::MODELS << [tag, uri, occurs, getter, plural]
        end
      end

      def install_get_attribute(name, uri, required=true,
                                type=nil, disp_name=nil,
                                element_name=nil)
        disp_name ||= name
        element_name ||= name
        writer_type, reader_type = type
        def_corresponded_attr_writer name, writer_type, disp_name
        def_corresponded_attr_reader name, reader_type
        if type == :boolean and /^is/ =~ name
          alias_method "#{$POSTMATCH}?", name
        end
        self::GET_ATTRIBUTES << [name, uri, required, element_name]
        add_need_initialize_variable(disp_name)
      end

      def def_corresponded_attr_writer(name, type=nil, disp_name=nil)
        disp_name ||= name
        case type
        when :integer
          integer_writer name, disp_name
        when :positive_integer
          positive_integer_writer name, disp_name
        when :boolean
          boolean_writer name, disp_name
        when :w3cdtf, :rfc822, :rfc2822
          date_writer name, type, disp_name
        when :text_type
          text_type_writer name, disp_name
        when :content
          content_writer name, disp_name
        when :explicit_clean_other
          explicit_clean_other_writer name, disp_name
        when :yes_other
          yes_other_writer name, disp_name
        when :csv
          csv_writer name
        when :csv_integer
          csv_integer_writer name
        else
          attr_writer name
        end
      end

      def def_corresponded_attr_reader(name, type=nil)
        case type
        when :inherit
          inherit_convert_attr_reader name
        when :uri
          uri_convert_attr_reader name
        when :explicit_clean_other
          explicit_clean_other_attr_reader name
        when :yes_other
          yes_other_attr_reader name
        when :csv
          csv_attr_reader name
        when :csv_integer
          csv_attr_reader name, :separator => ","
        else
          convert_attr_reader name
        end
      end

      def content_setup(type=nil, disp_name=nil)
        writer_type, reader_type = type
        def_corresponded_attr_writer :content, writer_type, disp_name
        def_corresponded_attr_reader :content, reader_type
        @have_content = true
      end

      def have_content?
        @have_content
      end

      def add_have_children_element(variable_name, plural_name)
        self::HAVE_CHILDREN_ELEMENTS << [variable_name, plural_name]
      end

      def add_to_element_method(method_name)
        self::TO_ELEMENT_METHODS << method_name
      end

      def add_need_initialize_variable(variable_name)
        self::NEED_INITIALIZE_VARIABLES << variable_name
      end

      def add_plural_form(singular, plural)
        self::PLURAL_FORMS[singular] = plural
      end

      def required_prefix
        nil
      end

      def required_uri
        ""
      end

      def need_parent?
        false
      end

      def install_ns(prefix, uri)
        if self::NSPOOL.has_key?(prefix)
          raise OverlappedPrefixError.new(prefix)
        end
        self::NSPOOL[prefix] = uri
      end

      def tag_name
        @tag_name
      end
    end

    attr_accessor :parent, :do_validate

    def initialize(do_validate=true, attrs=nil)
      @parent = nil
      @converter = nil
      if attrs.nil? and (do_validate.is_a?(Hash) or do_validate.is_a?(Array))
        do_validate, attrs = true, do_validate
      end
      @do_validate = do_validate
      initialize_variables(attrs || {})
    end

    def tag_name
      self.class.tag_name
    end

    def full_name
      tag_name
    end

    def converter=(converter)
      @converter = converter
      targets = children.dup
      self.class.have_children_elements.each do |variable_name, plural_name|
        targets.concat(__send__(plural_name))
      end
      targets.each do |target|
        target.converter = converter unless target.nil?
      end
    end

    def convert(value)
      if @converter
        @converter.convert(value)
      else
        value
      end
    end

    def valid?(ignore_unknown_element=true)
      validate(ignore_unknown_element)
      true
    rescue RSS::Error
      false
    end

    def validate(ignore_unknown_element=true)
      do_validate = @do_validate
      @do_validate = true
      validate_attribute
      __validate(ignore_unknown_element)
    ensure
      @do_validate = do_validate
    end

    def validate_for_stream(tags, ignore_unknown_element=true)
      validate_attribute
      __validate(ignore_unknown_element, tags, false)
    end

    def to_s(need_convert=true, indent='')
      if self.class.have_content?
        return "" if !empty_content? and !content_is_set?
        rv = tag(indent) do |next_indent|
          if empty_content?
            ""
          else
            xmled_content
          end
        end
      else
        rv = tag(indent) do |next_indent|
          self.class.to_element_methods.collect do |method_name|
            __send__(method_name, false, next_indent)
          end
        end
      end
      rv = convert(rv) if need_convert
      rv
    end

    def have_xml_content?
      false
    end

    def need_base64_encode?
      false
    end

    def set_next_element(tag_name, next_element)
      klass = next_element.class
      prefix = ""
      prefix << "#{klass.required_prefix}_" if klass.required_prefix
      key = "#{prefix}#{tag_name.gsub(/-/, '_')}"
      if self.class.plural_forms.has_key?(key)
        ary = __send__("#{self.class.plural_forms[key]}")
        ary << next_element
      else
        __send__("#{key}=", next_element)
      end
    end

    protected
    def have_required_elements?
      self.class::MODELS.all? do |tag, uri, occurs, getter|
        if occurs.nil? or occurs == "+"
          child = __send__(getter)
          if child.is_a?(Array)
            children = child
            children.any? {|c| c.have_required_elements?}
          else
            not child.nil?
          end
        else
          true
        end
      end
    end

    private
    def initialize_variables(attrs)
      normalized_attrs = {}
      attrs.each do |key, value|
        normalized_attrs[key.to_s] = value
      end
      self.class.need_initialize_variables.each do |variable_name|
        value = normalized_attrs[variable_name.to_s]
        if value
          __send__("#{variable_name}=", value)
        else
          instance_variable_set("@#{variable_name}", nil)
        end
      end
      initialize_have_children_elements
      @content = normalized_attrs["content"] if self.class.have_content?
    end

    def initialize_have_children_elements
      self.class.have_children_elements.each do |variable_name, plural_name|
        instance_variable_set("@#{variable_name}", [])
      end
    end

    def tag(indent, additional_attrs={}, &block)
      next_indent = indent + INDENT

      attrs = collect_attrs
      return "" if attrs.nil?

      return "" unless have_required_elements?

      attrs.update(additional_attrs)
      start_tag = make_start_tag(indent, next_indent, attrs.dup)

      if block
        content = block.call(next_indent)
      else
        content = []
      end

      if content.is_a?(String)
        content = [content]
        start_tag << ">"
        end_tag = "</#{full_name}>"
      else
        content = content.reject{|x| x.empty?}
        if content.empty?
          return "" if attrs.empty?
          end_tag = "/>"
        else
          start_tag << ">\n"
          end_tag = "\n#{indent}</#{full_name}>"
        end
      end

      start_tag + content.join("\n") + end_tag
    end

    def make_start_tag(indent, next_indent, attrs)
      start_tag = ["#{indent}<#{full_name}"]
      unless attrs.empty?
        start_tag << attrs.collect do |key, value|
          %Q[#{h key}="#{h value}"]
        end.join("\n#{next_indent}")
      end
      start_tag.join(" ")
    end

    def collect_attrs
      attrs = {}
      _attrs.each do |name, required, alias_name|
        value = __send__(alias_name || name)
        return nil if required and value.nil?
        next if value.nil?
        return nil if attrs.has_key?(name)
        attrs[name] = value
      end
      attrs
    end

    def tag_name_with_prefix(prefix)
      "#{prefix}:#{tag_name}"
    end

    # For backward compatibility
    def calc_indent
      ''
    end

    def children
      rv = []
      self.class.models.each do |name, uri, occurs, getter|
        value = __send__(getter)
        next if value.nil?
        value = [value] unless value.is_a?(Array)
        value.each do |v|
          rv << v if v.is_a?(Element)
        end
      end
      rv
    end

    def _tags
      rv = []
      self.class.models.each do |name, uri, occurs, getter, plural|
        value = __send__(getter)
        next if value.nil?
        if plural and value.is_a?(Array)
          rv.concat([[uri, name]] * value.size)
        else
          rv << [uri, name]
        end
      end
      rv
    end

    def _attrs
      self.class.get_attributes.collect do |name, uri, required, element_name|
        [element_name, required, name]
      end
    end

    def __validate(ignore_unknown_element, tags=_tags, recursive=true)
      if recursive
        children.compact.each do |child|
          child.validate
        end
      end
      must_call_validators = self.class.must_call_validators
      tags = tag_filter(tags.dup)
      p tags if DEBUG
      must_call_validators.each do |uri, prefix|
        _validate(ignore_unknown_element, tags[uri], uri)
        meth = "#{prefix}_validate"
        if !prefix.empty? and respond_to?(meth, true)
          __send__(meth, ignore_unknown_element, tags[uri], uri)
        end
      end
    end

    def validate_attribute
      _attrs.each do |a_name, required, alias_name|
        value = instance_variable_get("@#{alias_name || a_name}")
        if required and value.nil?
          raise MissingAttributeError.new(tag_name, a_name)
        end
        __send__("#{alias_name || a_name}=", value)
      end
    end

    def _validate(ignore_unknown_element, tags, uri, models=self.class.models)
      count = 1
      do_redo = false
      not_shift = false
      tag = nil
      models = models.find_all {|model| model[1] == uri}
      element_names = models.collect {|model| model[0]}
      if tags
        tags_size = tags.size
        tags = tags.sort_by {|x| element_names.index(x) || tags_size}
      end

      models.each_with_index do |model, i|
        name, _, occurs, = model

        if DEBUG
          p "before"
          p tags
          p model
        end

        if not_shift
          not_shift = false
        elsif tags
          tag = tags.shift
        end

        if DEBUG
          p "mid"
          p count
        end

        case occurs
        when '?'
          if count > 2
            raise TooMuchTagError.new(name, tag_name)
          else
            if name == tag
              do_redo = true
            else
              not_shift = true
            end
          end
        when '*'
          if name == tag
            do_redo = true
          else
            not_shift = true
          end
        when '+'
          if name == tag
            do_redo = true
          else
            if count > 1
              not_shift = true
            else
              raise MissingTagError.new(name, tag_name)
            end
          end
        else
          if name == tag
            if models[i+1] and models[i+1][0] != name and
                tags and tags.first == name
              raise TooMuchTagError.new(name, tag_name)
            end
          else
            raise MissingTagError.new(name, tag_name)
          end
        end

        if DEBUG
          p "after"
          p not_shift
          p do_redo
          p tag
        end

        if do_redo
          do_redo = false
          count += 1
          redo
        else
          count = 1
        end

      end

      if !ignore_unknown_element and !tags.nil? and !tags.empty?
        raise NotExpectedTagError.new(tags.first, uri, tag_name)
      end

    end

    def tag_filter(tags)
      rv = {}
      tags.each do |tag|
        rv[tag[0]] = [] unless rv.has_key?(tag[0])
        rv[tag[0]].push(tag[1])
      end
      rv
    end

    def empty_content?
      false
    end

    def content_is_set?
      if have_xml_content?
        __send__(self.class.xml_getter)
      else
        content
      end
    end

    def xmled_content
      if have_xml_content?
        __send__(self.class.xml_getter).to_s
      else
        _content = content
        _content = [_content].pack("m0") if need_base64_encode?
        h(_content)
      end
    end
  end

  module RootElementMixin

    include XMLStyleSheetMixin

    attr_reader :output_encoding
    attr_reader :feed_type, :feed_subtype, :feed_version
    attr_accessor :version, :encoding, :standalone
    def initialize(feed_version, version=nil, encoding=nil, standalone=nil)
      super()
      @feed_type = nil
      @feed_subtype = nil
      @feed_version = feed_version
      @version = version || '1.0'
      @encoding = encoding
      @standalone = standalone
      @output_encoding = nil
    end

    def feed_info
      [@feed_type, @feed_version, @feed_subtype]
    end

    def output_encoding=(enc)
      @output_encoding = enc
      self.converter = Converter.new(@output_encoding, @encoding)
    end

    def setup_maker(maker)
      maker.version = version
      maker.encoding = encoding
      maker.standalone = standalone

      xml_stylesheets.each do |xss|
        xss.setup_maker(maker)
      end

      super
    end

    def to_feed(type, &block)
      Maker.make(type) do |maker|
        setup_maker(maker)
        block.call(maker) if block
      end
    end

    def to_rss(type, &block)
      to_feed("rss#{type}", &block)
    end

    def to_atom(type, &block)
      to_feed("atom:#{type}", &block)
    end

    def to_xml(type=nil, &block)
      if type.nil? or same_feed_type?(type)
        to_s
      else
        to_feed(type, &block).to_s
      end
    end

    private
    def same_feed_type?(type)
      if /^(atom|rss)?(\d+\.\d+)?(?::(.+))?$/i =~ type
        feed_type = ($1 || @feed_type).downcase
        feed_version = $2 || @feed_version
        feed_subtype = $3 || @feed_subtype
        [feed_type, feed_version, feed_subtype] == feed_info
      else
        false
      end
    end

    def tag(indent, attrs={}, &block)
      rv = super(indent, ns_declarations.merge(attrs), &block)
      return rv if rv.empty?
      "#{xmldecl}#{xml_stylesheet_pi}#{rv}"
    end

    def xmldecl
      rv = %Q[<?xml version="#{@version}"]
      if @output_encoding or @encoding
        rv << %Q[ encoding="#{@output_encoding or @encoding}"]
      end
      rv << %Q[ standalone="yes"] if @standalone
      rv << "?>\n"
      rv
    end

    def ns_declarations
      decls = {}
      self.class::NSPOOL.collect do |prefix, uri|
        prefix = ":#{prefix}" unless prefix.empty?
        decls["xmlns#{prefix}"] = uri
      end
      decls
    end

    def maker_target(target)
      target
    end
  end
end
