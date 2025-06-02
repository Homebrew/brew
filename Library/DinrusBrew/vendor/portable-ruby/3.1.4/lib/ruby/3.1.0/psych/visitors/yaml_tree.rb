# frozen_string_literal: true
require_relative '../tree_builder'
require_relative '../scalar_scanner'
require_relative '../class_loader'

module Psych
  module Visitors
    ###
    # YAMLTree builds a YAML ast given a Ruby object.  For example:
    #
    #   builder = Psych::Visitors::YAMLTree.new
    #   builder << { :foo => 'bar' }
    #   builder.tree # => #<Psych::Nodes::Stream .. }
    #
    class YAMLTree < Psych::Visitors::Visitor
      class Registrar # :nodoc:
        def initialize
          @obj_to_id   = {}
          @obj_to_node = {}
          @targets     = []
          @counter     = 0
        end

        def register target, node
          return unless target.respond_to? :object_id
          @targets << target
          @obj_to_node[target.object_id] = node
        end

        def key? target
          @obj_to_node.key? target.object_id
        rescue NoMethodError
          false
        end

        def id_for target
          @obj_to_id[target.object_id] ||= (@counter += 1)
        end

        def node_for target
          @obj_to_node[target.object_id]
        end
      end

      attr_reader :started, :finished
      alias :finished? :finished
      alias :started? :started

      def self.create options = {}, emitter = nil
        emitter      ||= TreeBuilder.new
        class_loader = ClassLoader.new
        ss           = ScalarScanner.new class_loader
        new(emitter, ss, options)
      end

      def initialize emitter, ss, options
        super()
        @started    = false
        @finished   = false
        @emitter    = emitter
        @st         = Registrar.new
        @ss         = ss
        @options    = options
        @line_width = options[:line_width]
        if @line_width && @line_width < 0
          if @line_width == -1
            # Treat -1 as unlimited line-width, same as libyaml does.
            @line_width = nil
          else
            fail(ArgumentError, "Invalid line_width #{@line_width}, must be non-negative or -1 for unlimited.")
          end
        end
        @coders     = []

        @dispatch_cache = Hash.new do |h,klass|
          method = "visit_#{(klass.name || '').split('::').join('_')}"

          method = respond_to?(method) ? method : h[klass.superclass]

          raise(TypeError, "Can't dump #{target.class}") unless method

          h[klass] = method
        end.compare_by_identity
      end

      def start encoding = Nodes::Stream::UTF8
        @emitter.start_stream(encoding).tap do
          @started = true
        end
      end

      def finish
        @emitter.end_stream.tap do
          @finished = true
        end
      end

      def tree
        finish unless finished?
        @emitter.root
      end

      def push object
        start unless started?
        version = []
        version = [1,1] if @options[:header]

        case @options[:version]
        when Array
          version = @options[:version]
        when String
          version = @options[:version].split('.').map { |x| x.to_i }
        else
          version = [1,1]
        end if @options.key? :version

        @emitter.start_document version, [], false
        accept object
        @emitter.end_document !@emitter.streaming?
      end
      alias :<< :push

      def accept target
        # return any aliases we find
        if @st.key? target
          oid         = @st.id_for target
          node        = @st.node_for target
          anchor      = oid.to_s
          node.anchor = anchor
          return @emitter.alias anchor
        end

        if target.respond_to?(:encode_with)
          dump_coder target
        else
          send(@dispatch_cache[target.class], target)
        end
      end

      def visit_Psych_Omap o
        seq = @emitter.start_sequence(nil, 'tag:yaml.org,2002:omap', false, Nodes::Sequence::BLOCK)
        register(o, seq)

        o.each { |k,v| visit_Hash k => v }
        @emitter.end_sequence
      end

      def visit_Encoding o
        tag = "!ruby/encoding"
        @emitter.scalar o.name, nil, tag, false, false, Nodes::Scalar::ANY
      end

      def visit_Object o
        tag = Psych.dump_tags[o.class]
        unless tag
          klass = o.class == Object ? nil : o.class.name
          tag   = ['!ruby/object', klass].compact.join(':')
        end

        map = @emitter.start_mapping(nil, tag, false, Nodes::Mapping::BLOCK)
        register(o, map)

        dump_ivars o
        @emitter.end_mapping
      end

      alias :visit_Delegator :visit_Object

      def visit_Struct o
        tag = ['!ruby/struct', o.class.name].compact.join(':')

        register o, @emitter.start_mapping(nil, tag, false, Nodes::Mapping::BLOCK)
        o.members.each do |member|
          @emitter.scalar member.to_s, nil, nil, true, false, Nodes::Scalar::ANY
          accept o[member]
        end

        dump_ivars o

        @emitter.end_mapping
      end

      def visit_Exception o
        dump_exception o, o.message.to_s
      end

      def visit_NameError o
        dump_exception o, o.message.to_s
      end

      def visit_Regexp o
        register o, @emitter.scalar(o.inspect, nil, '!ruby/regexp', false, false, Nodes::Scalar::ANY)
      end

      def visit_DateTime o
        formatted = if o.offset.zero?
                      o.strftime("%Y-%m-%d %H:%M:%S.%9N Z".freeze)
                    else
                      o.strftime("%Y-%m-%d %H:%M:%S.%9N %:z".freeze)
                    end
        tag = '!ruby/object:DateTime'
        register o, @emitter.scalar(formatted, nil, tag, false, false, Nodes::Scalar::ANY)
      end

      def visit_Time o
        formatted = format_time o
        register o, @emitter.scalar(formatted, nil, nil, true, false, Nodes::Scalar::ANY)
      end

      def visit_Rational o
        register o, @emitter.start_mapping(nil, '!ruby/object:Rational', false, Nodes::Mapping::BLOCK)

        [
          'denominator', o.denominator.to_s,
          'numerator', o.numerator.to_s
        ].each do |m|
          @emitter.scalar m, nil, nil, true, false, Nodes::Scalar::ANY
        end

        @emitter.end_mapping
      end

      def visit_Complex o
        register o, @emitter.start_mapping(nil, '!ruby/object:Complex', false, Nodes::Mapping::BLOCK)

        ['real', o.real.to_s, 'image', o.imag.to_s].each do |m|
          @emitter.scalar m, nil, nil, true, false, Nodes::Scalar::ANY
        end

        @emitter.end_mapping
      end

      def visit_Integer o
        @emitter.scalar o.to_s, nil, nil, true, false, Nodes::Scalar::ANY
      end
      alias :visit_TrueClass :visit_Integer
      alias :visit_FalseClass :visit_Integer
      alias :visit_Date :visit_Integer

      def visit_Float o
        if o.nan?
          @emitter.scalar '.nan', nil, nil, true, false, Nodes::Scalar::ANY
        elsif o.infinite?
          @emitter.scalar((o.infinite? > 0 ? '.inf' : '-.inf'),
            nil, nil, true, false, Nodes::Scalar::ANY)
        else
          @emitter.scalar o.to_s, nil, nil, true, false, Nodes::Scalar::ANY
        end
      end

      def visit_BigDecimal o
        @emitter.scalar o._dump, nil, '!ruby/object:BigDecimal', false, false, Nodes::Scalar::ANY
      end

      def visit_String o
        plain = true
        quote = true
        style = Nodes::Scalar::PLAIN
        tag   = nil

        if binary?(o)
          o     = [o].pack('m0')
          tag   = '!binary' # FIXME: change to below when syck is removed
          #tag   = 'tag:yaml.org,2002:binary'
          style = Nodes::Scalar::LITERAL
          plain = false
          quote = false
        elsif o =~ /\n(?!\Z)/  # match \n except blank line at the end of string
          style = Nodes::Scalar::LITERAL
        elsif o == '<<'
          style = Nodes::Scalar::SINGLE_QUOTED
          tag   = 'tag:yaml.org,2002:str'
          plain = false
          quote = false
        elsif o == 'y' || o == 'n'
          style = Nodes::Scalar::DOUBLE_QUOTED
        elsif @line_width && o.length > @line_width
          style = Nodes::Scalar::FOLDED
        elsif o =~ /^[^[:word:]][^"]*$/
          style = Nodes::Scalar::DOUBLE_QUOTED
        elsif not String === @ss.tokenize(o) or /\A0[0-7]*[89]/ =~ o
          style = Nodes::Scalar::SINGLE_QUOTED
        end

        is_primitive = o.class == ::String
        ivars = is_primitive ? [] : o.instance_variables

        if ivars.empty?
          unless is_primitive
            tag = "!ruby/string:#{o.class}"
            plain = false
            quote = false
          end
          @emitter.scalar o, nil, tag, plain, quote, style
        else
          maptag = '!ruby/string'.dup
          maptag << ":#{o.class}" unless o.class == ::String

          register o, @emitter.start_mapping(nil, maptag, false, Nodes::Mapping::BLOCK)
          @emitter.scalar 'str', nil, nil, true, false, Nodes::Scalar::ANY
          @emitter.scalar o, nil, tag, plain, quote, style

          dump_ivars o

          @emitter.end_mapping
        end
      end

      def visit_Module o
        raise TypeError, "can't dump anonymous module: #{o}" unless o.name
        register o, @emitter.scalar(o.name, nil, '!ruby/module', false, false, Nodes::Scalar::SINGLE_QUOTED)
      end

      def visit_Class o
        raise TypeError, "can't dump anonymous class: #{o}" unless o.name
        register o, @emitter.scalar(o.name, nil, '!ruby/class', false, false, Nodes::Scalar::SINGLE_QUOTED)
      end

      def visit_Range o
        register o, @emitter.start_mapping(nil, '!ruby/range', false, Nodes::Mapping::BLOCK)
        ['begin', o.begin, 'end', o.end, 'excl', o.exclude_end?].each do |m|
          accept m
        end
        @emitter.end_mapping
      end

      def visit_Hash o
        if o.class == ::Hash
          register(o, @emitter.start_mapping(nil, nil, true, Psych::Nodes::Mapping::BLOCK))
          o.each do |k,v|
            accept k
            accept v
          end
          @emitter.end_mapping
        else
          visit_hash_subclass o
        end
      end

      def visit_Psych_Set o
        register(o, @emitter.start_mapping(nil, '!set', false, Psych::Nodes::Mapping::BLOCK))

        o.each do |k,v|
          accept k
          accept v
        end

        @emitter.end_mapping
      end

      def visit_Array o
        if o.class == ::Array
          visit_Enumerator o
        else
          visit_array_subclass o
        end
      end

      def visit_Enumerator o
        register o, @emitter.start_sequence(nil, nil, true, Nodes::Sequence::BLOCK)
        o.each { |c| accept c }
        @emitter.end_sequence
      end

      def visit_NilClass o
        @emitter.scalar('', nil, 'tag:yaml.org,2002:null', true, false, Nodes::Scalar::ANY)
      end

      def visit_Symbol o
        if o.empty?
          @emitter.scalar "", nil, '!ruby/symbol', false, false, Nodes::Scalar::ANY
        else
          @emitter.scalar ":#{o}", nil, nil, true, false, Nodes::Scalar::ANY
        end
      end

      def visit_BasicObject o
        tag = Psych.dump_tags[o.class]
        tag ||= "!ruby/marshalable:#{o.class.name}"

        map = @emitter.start_mapping(nil, tag, false, Nodes::Mapping::BLOCK)
        register(o, map)

        o.marshal_dump.each(&method(:accept))

        @emitter.end_mapping
      end

      private

      def binary? string
        string.encoding == Encoding::ASCII_8BIT && !string.ascii_only?
      end

      def visit_array_subclass o
        tag = "!ruby/array:#{o.class}"
        ivars = o.instance_variables
        if ivars.empty?
          node = @emitter.start_sequence(nil, tag, false, Nodes::Sequence::BLOCK)
          register o, node
          o.each { |c| accept c }
          @emitter.end_sequence
        else
          node = @emitter.start_mapping(nil, tag, false, Nodes::Sequence::BLOCK)
          register o, node

          # Dump the internal list
          accept 'internal'
          @emitter.start_sequence(nil, nil, true, Nodes::Sequence::BLOCK)
          o.each { |c| accept c }
          @emitter.end_sequence

          # Dump the ivars
          accept 'ivars'
          @emitter.start_mapping(nil, nil, true, Nodes::Sequence::BLOCK)
          ivars.each do |ivar|
            accept ivar
            accept o.instance_variable_get ivar
          end
          @emitter.end_mapping

          @emitter.end_mapping
        end
      end

      def visit_hash_subclass o
        ivars = o.instance_variables
        if ivars.any?
          tag = "!ruby/hash-with-ivars:#{o.class}"
          node = @emitter.start_mapping(nil, tag, false, Psych::Nodes::Mapping::BLOCK)
          register(o, node)

          # Dump the ivars
          accept 'ivars'
          @emitter.start_mapping nil, nil, true, Nodes::Mapping::BLOCK
          o.instance_variables.each do |ivar|
            accept ivar
            accept o.instance_variable_get ivar
          end
          @emitter.end_mapping

          # Dump the elements
          accept 'elements'
          @emitter.start_mapping nil, nil, true, Nodes::Mapping::BLOCK
          o.each do |k,v|
            accept k
            accept v
          end
          @emitter.end_mapping

          @emitter.end_mapping
        else
          tag = "!ruby/hash:#{o.class}"
          node = @emitter.start_mapping(nil, tag, false, Psych::Nodes::Mapping::BLOCK)
          register(o, node)
          o.each do |k,v|
            accept k
            accept v
          end
          @emitter.end_mapping
        end
      end

      def dump_list o
      end

      def dump_exception o, msg
        tag = ['!ruby/exception', o.class.name].join ':'

        @emitter.start_mapping nil, tag, false, Nodes::Mapping::BLOCK

        if msg
          @emitter.scalar 'message', nil, nil, true, false, Nodes::Scalar::ANY
          accept msg
        end

        @emitter.scalar 'backtrace', nil, nil, true, false, Nodes::Scalar::ANY
        accept o.backtrace

        dump_ivars o

        @emitter.end_mapping
      end

      def format_time time
        if time.utc?
          time.strftime("%Y-%m-%d %H:%M:%S.%9N Z")
        else
          time.strftime("%Y-%m-%d %H:%M:%S.%9N %:z")
        end
      end

      def register target, yaml_obj
        @st.register target, yaml_obj
        yaml_obj
      end

      def dump_coder o
        @coders << o
        tag = Psych.dump_tags[o.class]
        unless tag
          klass = o.class == Object ? nil : o.class.name
          tag   = ['!ruby/object', klass].compact.join(':')
        end

        c = Psych::Coder.new(tag)
        o.encode_with(c)
        emit_coder c, o
      end

      def emit_coder c, o
        case c.type
        when :scalar
          @emitter.scalar c.scalar, nil, c.tag, c.tag.nil?, false, c.style
        when :seq
          @emitter.start_sequence nil, c.tag, c.tag.nil?, c.style
          c.seq.each do |thing|
            accept thing
          end
          @emitter.end_sequence
        when :map
          register o, @emitter.start_mapping(nil, c.tag, c.implicit, c.style)
          c.map.each do |k,v|
            accept k
            accept v
          end
          @emitter.end_mapping
        when :object
          accept c.object
        end
      end

      def dump_ivars target
        target.instance_variables.each do |iv|
          @emitter.scalar("#{iv.to_s.sub(/^@/, '')}", nil, nil, true, false, Nodes::Scalar::ANY)
          accept target.instance_variable_get(iv)
        end
      end
    end

    class RestrictedYAMLTree < YAMLTree
      DEFAULT_PERMITTED_CLASSES = {
        TrueClass => true,
        FalseClass => true,
        NilClass => true,
        Integer => true,
        Float => true,
        String => true,
        Array => true,
        Hash => true,
      }.compare_by_identity.freeze

      def initialize emitter, ss, options
        super
        @permitted_classes = DEFAULT_PERMITTED_CLASSES.dup
        Array(options[:permitted_classes]).each do |klass|
          @permitted_classes[klass] = true
        end
        @permitted_symbols = {}.compare_by_identity
        Array(options[:permitted_symbols]).each do |symbol|
          @permitted_symbols[symbol] = true
        end
        @aliases = options.fetch(:aliases, false)
      end

      def accept target
        if !@aliases && @st.key?(target)
          raise BadAlias, "Tried to dump an aliased object"
        end

        unless @permitted_classes[target.class]
          raise DisallowedClass.new('dump', target.class.name || target.class.inspect)
        end

        super
      end

      def visit_Symbol sym
        unless @permitted_symbols[sym]
          raise DisallowedClass.new('dump', "Symbol(#{sym.inspect})")
        end

        super
      end
    end
  end
end
