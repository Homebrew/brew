# frozen_string_literal: false
require "forwardable"
require "open-uri"

require_relative "rss"
require_relative "xml"

module RSS

  class NotWellFormedError < Error
    attr_reader :line, :element

    # Create a new NotWellFormedError for an error at +line+
    # in +element+.  If a block is given the return value of
    # the block ends up in the error message.
    def initialize(line=nil, element=nil)
      message = "This is not well formed XML"
      if element or line
        message << "\nerror occurred"
        message << " in #{element}" if element
        message << " at about #{line} line" if line
      end
      message << "\n#{yield}" if block_given?
      super(message)
    end
  end

  class XMLParserNotFound < Error
    def initialize
      super("available XML parser was not found in " <<
            "#{AVAILABLE_PARSER_LIBRARIES.inspect}.")
    end
  end

  class NotValidXMLParser < Error
    def initialize(parser)
      super("#{parser} is not an available XML parser. " <<
            "Available XML parser" <<
            (AVAILABLE_PARSERS.size > 1 ? "s are " : " is ") <<
            "#{AVAILABLE_PARSERS.inspect}.")
    end
  end

  class NSError < InvalidRSSError
    attr_reader :tag, :prefix, :uri
    def initialize(tag, prefix, require_uri)
      @tag, @prefix, @uri = tag, prefix, require_uri
      super("prefix <#{prefix}> doesn't associate uri " <<
            "<#{require_uri}> in tag <#{tag}>")
    end
  end

  class Parser

    extend Forwardable

    class << self

      @@default_parser = nil

      def default_parser
        @@default_parser || AVAILABLE_PARSERS.first
      end

      # Set @@default_parser to new_value if it is one of the
      # available parsers. Else raise NotValidXMLParser error.
      def default_parser=(new_value)
        if AVAILABLE_PARSERS.include?(new_value)
          @@default_parser = new_value
        else
          raise NotValidXMLParser.new(new_value)
        end
      end

      def parse(rss, *args)
        if args.last.is_a?(Hash)
          options = args.pop
        else
          options = {}
        end
        do_validate = boolean_argument(args[0], options[:validate], true)
        ignore_unknown_element =
          boolean_argument(args[1], options[:ignore_unknown_element], true)
        parser_class = args[2] || options[:parser_class] || default_parser
        parser = new(rss, parser_class)
        parser.do_validate = do_validate
        parser.ignore_unknown_element = ignore_unknown_element
        parser.parse
      end

      private
      def boolean_argument(positioned_value, option_value, default)
        value = positioned_value
        if value.nil? and not option_value.nil?
          value = option_value
        end
        value = default if value.nil?
        value
      end
    end

    def_delegators(:@parser, :parse, :rss,
                   :ignore_unknown_element,
                   :ignore_unknown_element=, :do_validate,
                   :do_validate=)

    def initialize(rss, parser_class=self.class.default_parser)
      @parser = parser_class.new(normalize_rss(rss))
    end

    private

    # Try to get the XML associated with +rss+.
    # Return +rss+ if it already looks like XML, or treat it as a URI,
    # or a file to get the XML,
    def normalize_rss(rss)
      return rss if maybe_xml?(rss)

      uri = to_uri(rss)

      if uri.respond_to?(:read)
        uri.read
      elsif (RUBY_VERSION >= '2.7' || !rss.tainted?) and File.readable?(rss)
        File.open(rss) {|f| f.read}
      else
        rss
      end
    end

    # maybe_xml? tests if source is a string that looks like XML.
    def maybe_xml?(source)
      source.is_a?(String) and /</ =~ source
    end

    # Attempt to convert rss to a URI, but just return it if
    # there's a ::URI::Error
    def to_uri(rss)
      return rss if rss.is_a?(::URI::Generic)

      begin
        ::URI.parse(rss)
      rescue ::URI::Error
        rss
      end
    end
  end

  class BaseParser

    class << self
      def raise_for_undefined_entity?
        listener.raise_for_undefined_entity?
      end
    end

    def initialize(rss)
      @listener = self.class.listener.new
      @rss = rss
    end

    def rss
      @listener.rss
    end

    def ignore_unknown_element
      @listener.ignore_unknown_element
    end

    def ignore_unknown_element=(new_value)
      @listener.ignore_unknown_element = new_value
    end

    def do_validate
      @listener.do_validate
    end

    def do_validate=(new_value)
      @listener.do_validate = new_value
    end

    def parse
      if @listener.rss.nil?
        _parse
      end
      @listener.rss
    end

  end

  class BaseListener

    extend Utils

    class << self

      @@accessor_bases = {}
      @@registered_uris = {}
      @@class_names = {}

      # return the setter for the uri, tag_name pair, or nil.
      def setter(uri, tag_name)
        _getter = getter(uri, tag_name)
        if _getter
          "#{_getter}="
        else
          nil
        end
      end

      def getter(uri, tag_name)
        (@@accessor_bases[uri] || {})[tag_name]
      end

      # return the tag_names for setters associated with uri
      def available_tags(uri)
        (@@accessor_bases[uri] || {}).keys
      end

      # register uri against this name.
      def register_uri(uri, name)
        @@registered_uris[name] ||= {}
        @@registered_uris[name][uri] = nil
      end

      # test if this uri is registered against this name
      def uri_registered?(uri, name)
        @@registered_uris[name].has_key?(uri)
      end

      # record class_name for the supplied uri and tag_name
      def install_class_name(uri, tag_name, class_name)
        @@class_names[uri] ||= {}
        @@class_names[uri][tag_name] = class_name
      end

      # retrieve class_name for the supplied uri and tag_name
      # If it doesn't exist, capitalize the tag_name
      def class_name(uri, tag_name)
        name = (@@class_names[uri] || {})[tag_name]
        return name if name

        tag_name = tag_name.gsub(/[_\-]([a-z]?)/) {$1.upcase}
        tag_name[0, 1].upcase + tag_name[1..-1]
      end

      def install_get_text_element(uri, name, accessor_base)
        install_accessor_base(uri, name, accessor_base)
        def_get_text_element(uri, name, *get_file_and_line_from_caller(1))
      end

      def raise_for_undefined_entity?
        true
      end

      private
      # set the accessor for the uri, tag_name pair
      def install_accessor_base(uri, tag_name, accessor_base)
        @@accessor_bases[uri] ||= {}
        @@accessor_bases[uri][tag_name] = accessor_base.chomp("=")
      end

      def def_get_text_element(uri, element_name, file, line)
        register_uri(uri, element_name)
        method_name = "start_#{element_name}"
        unless private_method_defined?(method_name)
          define_method(method_name) do |name, prefix, attrs, ns|
            uri = _ns(ns, prefix)
            if self.class.uri_registered?(uri, element_name)
              start_get_text_element(name, prefix, ns, uri)
            else
              start_else_element(name, prefix, attrs, ns)
            end
          end
          private(method_name)
        end
      end
    end
  end

  module ListenerMixin
    attr_reader :rss

    attr_accessor :ignore_unknown_element
    attr_accessor :do_validate

    def initialize
      @rss = nil
      @ignore_unknown_element = true
      @do_validate = true
      @ns_stack = [{"xml" => :xml}]
      @tag_stack = [[]]
      @text_stack = ['']
      @proc_stack = []
      @last_element = nil
      @version = @encoding = @standalone = nil
      @xml_stylesheets = []
      @xml_child_mode = false
      @xml_element = nil
      @last_xml_element = nil
    end

    # set instance vars for version, encoding, standalone
    def xmldecl(version, encoding, standalone)
      @version, @encoding, @standalone = version, encoding, standalone
    end

    def instruction(name, content)
      if name == "xml-stylesheet"
        params = parse_pi_content(content)
        if params.has_key?("href")
          @xml_stylesheets << XMLStyleSheet.new(params)
        end
      end
    end

    def tag_start(name, attributes)
      @text_stack.push('')

      ns = @ns_stack.last.dup
      attrs = {}
      attributes.each do |n, v|
        if /\Axmlns(?:\z|:)/ =~ n
          ns[$POSTMATCH] = v
        else
          attrs[n] = v
        end
      end
      @ns_stack.push(ns)

      prefix, local = split_name(name)
      @tag_stack.last.push([_ns(ns, prefix), local])
      @tag_stack.push([])
      if @xml_child_mode
        previous = @last_xml_element
        element_attrs = attributes.dup
        unless previous
          ns.each do |ns_prefix, value|
            next if ns_prefix == "xml"
            key = ns_prefix.empty? ? "xmlns" : "xmlns:#{ns_prefix}"
            element_attrs[key] ||= value
          end
        end
        next_element = XML::Element.new(local,
                                        prefix.empty? ? nil : prefix,
                                        _ns(ns, prefix),
                                        element_attrs)
        previous << next_element if previous
        @last_xml_element = next_element
        pr = Proc.new do |text, tags|
          if previous
            @last_xml_element = previous
          else
            @xml_element = @last_xml_element
            @last_xml_element = nil
          end
        end
        @proc_stack.push(pr)
      else
        if @rss.nil? and respond_to?("initial_start_#{local}", true)
          __send__("initial_start_#{local}", local, prefix, attrs, ns.dup)
        elsif respond_to?("start_#{local}", true)
          __send__("start_#{local}", local, prefix, attrs, ns.dup)
        else
          start_else_element(local, prefix, attrs, ns.dup)
        end
      end
    end

    def tag_end(name)
      if DEBUG
        p "end tag #{name}"
        p @tag_stack
      end
      text = @text_stack.pop
      tags = @tag_stack.pop
      pr = @proc_stack.pop
      pr.call(text, tags) unless pr.nil?
      @ns_stack.pop
    end

    def text(data)
      if @xml_child_mode
        @last_xml_element << data if @last_xml_element
      else
        @text_stack.last << data
      end
    end

    private
    def _ns(ns, prefix)
      ns.fetch(prefix, "")
    end

    CONTENT_PATTERN = /\s*([^=]+)=(["'])([^\2]+?)\2/
    # Extract the first name="value" pair from content.
    # Works with single quotes according to the constant
    # CONTENT_PATTERN. Return a Hash.
    def parse_pi_content(content)
      params = {}
      content.scan(CONTENT_PATTERN) do |name, quote, value|
        params[name] = value
      end
      params
    end

    def start_else_element(local, prefix, attrs, ns)
      class_name = self.class.class_name(_ns(ns, prefix), local)
      current_class = @last_element.class
      if known_class?(current_class, class_name)
        next_class = current_class.const_get(class_name)
        start_have_something_element(local, prefix, attrs, ns, next_class)
      else
        if !@do_validate or @ignore_unknown_element
          @proc_stack.push(setup_next_element_in_unknown_element)
        else
          parent = "ROOT ELEMENT???"
          if current_class.tag_name
            parent = current_class.tag_name
          end
          raise NotExpectedTagError.new(local, _ns(ns, prefix), parent)
        end
      end
    end

    if Module.method(:const_defined?).arity == -1
      def known_class?(target_class, class_name)
        class_name and
          (target_class.const_defined?(class_name, false) or
           target_class.constants.include?(class_name.to_sym))
      end
    else
      def known_class?(target_class, class_name)
        class_name and
          (target_class.const_defined?(class_name) or
           target_class.constants.include?(class_name))
      end
    end

    NAMESPLIT = /^(?:([\w:][-\w.]*):)?([\w:][-\w.]*)/
    def split_name(name)
      name =~ NAMESPLIT
      [$1 || '', $2]
    end

    def check_ns(tag_name, prefix, ns, require_uri, ignore_unknown_element=nil)
      if _ns(ns, prefix) == require_uri
        true
      else
        if ignore_unknown_element.nil?
          ignore_unknown_element = @ignore_unknown_element
        end

        if ignore_unknown_element
          false
        elsif @do_validate
          raise NSError.new(tag_name, prefix, require_uri)
        else
          # Force bind required URI with prefix
          @ns_stack.last[prefix] = require_uri
          true
        end
      end
    end

    def start_get_text_element(tag_name, prefix, ns, required_uri)
      pr = Proc.new do |text, tags|
        setter = self.class.setter(required_uri, tag_name)
        if setter and @last_element.respond_to?(setter)
          if @do_validate
            getter = self.class.getter(required_uri, tag_name)
            if @last_element.__send__(getter)
              raise TooMuchTagError.new(tag_name, @last_element.tag_name)
            end
          end
          @last_element.__send__(setter, text.to_s)
        else
          if @do_validate and !@ignore_unknown_element
            raise NotExpectedTagError.new(tag_name, _ns(ns, prefix),
                                          @last_element.tag_name)
          end
        end
      end
      @proc_stack.push(pr)
    end

    def start_have_something_element(tag_name, prefix, attrs, ns, klass)
      if check_ns(tag_name, prefix, ns, klass.required_uri)
        attributes = collect_attributes(tag_name, prefix, attrs, ns, klass)
        @proc_stack.push(setup_next_element(tag_name, klass, attributes))
      else
        @proc_stack.push(setup_next_element_in_unknown_element)
      end
    end

    def collect_attributes(tag_name, prefix, attrs, ns, klass)
      attributes = {}
      klass.get_attributes.each do |a_name, a_uri, required, element_name|
        if a_uri.is_a?(String) or !a_uri.respond_to?(:include?)
          a_uri = [a_uri]
        end
        unless a_uri == [""]
          for prefix, uri in ns
            if a_uri.include?(uri)
              val = attrs["#{prefix}:#{a_name}"]
              break if val
            end
          end
        end
        if val.nil? and a_uri.include?("")
          val = attrs[a_name]
        end

        if @do_validate and required and val.nil?
          unless a_uri.include?("")
            for prefix, uri in ns
              if a_uri.include?(uri)
                a_name = "#{prefix}:#{a_name}"
              end
            end
          end
          raise MissingAttributeError.new(tag_name, a_name)
        end

        attributes[a_name] = val
      end
      attributes
    end

    def setup_next_element(tag_name, klass, attributes)
      previous = @last_element
      next_element = klass.new(@do_validate, attributes)
      previous.set_next_element(tag_name, next_element)
      @last_element = next_element
      @last_element.parent = previous if klass.need_parent?
      @xml_child_mode = @last_element.have_xml_content?

      Proc.new do |text, tags|
        p(@last_element.class) if DEBUG
        if @xml_child_mode
          @last_element.content = @xml_element.to_s
          xml_setter = @last_element.class.xml_setter
          @last_element.__send__(xml_setter, @xml_element)
          @xml_element = nil
          @xml_child_mode = false
        else
          if klass.have_content?
            if @last_element.need_base64_encode?
              text = text.lstrip.unpack("m").first
            end
            @last_element.content = text
          end
        end
        if @do_validate
          @last_element.validate_for_stream(tags, @ignore_unknown_element)
        end
        @last_element = previous
      end
    end

    def setup_next_element_in_unknown_element
      current_element, @last_element = @last_element, nil
      Proc.new {@last_element = current_element}
    end
  end

  unless const_defined? :AVAILABLE_PARSER_LIBRARIES
    # The list of all available libraries for parsing.
    AVAILABLE_PARSER_LIBRARIES = [
      ["rss/xmlparser", :XMLParserParser],
      ["rss/xmlscanner", :XMLScanParser],
      ["rss/rexmlparser", :REXMLParser],
    ]
  end

  # The list of all available parsers, in constant form.
  AVAILABLE_PARSERS = []

  AVAILABLE_PARSER_LIBRARIES.each do |lib, parser|
    begin
      require lib
      AVAILABLE_PARSERS.push(const_get(parser))
    rescue LoadError
    end
  end

  if AVAILABLE_PARSERS.empty?
    raise XMLParserNotFound
  end
end
