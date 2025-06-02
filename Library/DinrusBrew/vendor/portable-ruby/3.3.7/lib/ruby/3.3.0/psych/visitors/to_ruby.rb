# frozen_string_literal: true
require_relative '../scalar_scanner'
require_relative '../class_loader'
require_relative '../exception'

unless defined?(Regexp::NOENCODING)
  Regexp::NOENCODING = 32
end

module Psych
  module Visitors
    ###
    # This class walks a YAML AST, converting each node to Ruby
    class ToRuby < Psych::Visitors::Visitor
      def self.create(symbolize_names: false, freeze: false, strict_integer: false)
        class_loader = ClassLoader.new
        scanner      = ScalarScanner.new class_loader, strict_integer: strict_integer
        new(scanner, class_loader, symbolize_names: symbolize_names, freeze: freeze)
      end

      attr_reader :class_loader

      def initialize ss, class_loader, symbolize_names: false, freeze: false
        super()
        @st = {}
        @ss = ss
        @load_tags = Psych.load_tags
        @domain_types = Psych.domain_types
        @class_loader = class_loader
        @symbolize_names = symbolize_names
        @freeze = freeze
      end

      def accept target
        result = super

        unless @domain_types.empty? || !target.tag
          key = target.tag.sub(/^[!\/]*/, '').sub(/(,\d+)\//, '\1:')
          key = "tag:#{key}" unless key =~ /^(?:tag:|x-private)/

          if @domain_types.key? key
            value, block = @domain_types[key]
            result = block.call value, result
          end
        end

        result = deduplicate(result).freeze if @freeze
        result
      end

      def deserialize o
        if klass = resolve_class(@load_tags[o.tag])
          instance = klass.allocate

          if instance.respond_to?(:init_with)
            coder = Psych::Coder.new(o.tag)
            coder.scalar = o.value
            instance.init_with coder
          end

          return instance
        end

        return o.value if o.quoted
        return @ss.tokenize(o.value) unless o.tag

        case o.tag
        when '!binary', 'tag:yaml.org,2002:binary'
          o.value.unpack('m').first
        when /^!(?:str|ruby\/string)(?::(.*))?$/, 'tag:yaml.org,2002:str'
          klass = resolve_class($1)
          if klass
            klass.allocate.replace o.value
          else
            o.value
          end
        when '!ruby/object:BigDecimal'
          require 'bigdecimal' unless defined? BigDecimal
          class_loader.big_decimal._load o.value
        when "!ruby/object:DateTime"
          class_loader.date_time
          require 'date' unless defined? DateTime
          t = @ss.parse_time(o.value)
          DateTime.civil(*t.to_a[0, 6].reverse, Rational(t.utc_offset, 86400)) +
            (t.subsec/86400)
        when '!ruby/encoding'
          ::Encoding.find o.value
        when "!ruby/object:Complex"
          class_loader.complex
          Complex(o.value)
        when "!ruby/object:Rational"
          class_loader.rational
          Rational(o.value)
        when "!ruby/class", "!ruby/module"
          resolve_class o.value
        when "tag:yaml.org,2002:float", "!float"
          Float(@ss.tokenize(o.value))
        when "!ruby/regexp"
          klass = class_loader.regexp
          o.value =~ /^\/(.*)\/([mixn]*)$/m
          source  = $1
          options = 0
          lang    = nil
          $2&.each_char do |option|
            case option
            when 'x' then options |= Regexp::EXTENDED
            when 'i' then options |= Regexp::IGNORECASE
            when 'm' then options |= Regexp::MULTILINE
            when 'n' then options |= Regexp::NOENCODING
            else lang = option
            end
          end
          klass.new(*[source, options, lang].compact)
        when "!ruby/range"
          klass = class_loader.range
          args = o.value.split(/([.]{2,3})/, 2).map { |s|
            accept Nodes::Scalar.new(s)
          }
          args.push(args.delete_at(1) == '...')
          klass.new(*args)
        when /^!ruby\/sym(bol)?:?(.*)?$/
          class_loader.symbolize o.value
        else
          @ss.tokenize o.value
        end
      end
      private :deserialize

      def visit_Psych_Nodes_Scalar o
        register o, deserialize(o)
      end

      def visit_Psych_Nodes_Sequence o
        if klass = resolve_class(@load_tags[o.tag])
          instance = klass.allocate

          if instance.respond_to?(:init_with)
            coder = Psych::Coder.new(o.tag)
            coder.seq = o.children.map { |c| accept c }
            instance.init_with coder
          end

          return instance
        end

        case o.tag
        when nil
          register_empty(o)
        when '!omap', 'tag:yaml.org,2002:omap'
          map = register(o, Psych::Omap.new)
          o.children.each { |a|
            map[accept(a.children.first)] = accept a.children.last
          }
          map
        when /^!(?:seq|ruby\/array):(.*)$/
          klass = resolve_class($1)
          list  = register(o, klass.allocate)
          o.children.each { |c| list.push accept c }
          list
        else
          register_empty(o)
        end
      end

      def visit_Psych_Nodes_Mapping o
        if @load_tags[o.tag]
          return revive(resolve_class(@load_tags[o.tag]), o)
        end
        return revive_hash(register(o, {}), o) unless o.tag

        case o.tag
        when /^!ruby\/struct:?(.*)?$/
          klass = resolve_class($1) if $1

          if klass
            s = register(o, klass.allocate)

            members = {}
            struct_members = s.members.map { |x| class_loader.symbolize x }
            o.children.each_slice(2) do |k,v|
              member = accept(k)
              value  = accept(v)
              if struct_members.include?(class_loader.symbolize(member))
                s.send("#{member}=", value)
              else
                members[member.to_s.sub(/^@/, '')] = value
              end
            end
            init_with(s, members, o)
          else
            klass = class_loader.struct
            members = o.children.map { |c| accept c }
            h = Hash[*members]
            s = klass.new(*h.map { |k,v|
              class_loader.symbolize k
            }).new(*h.map { |k,v| v })
            register(o, s)
            s
          end

        when /^!ruby\/object:?(.*)?$/
          name = $1 || 'Object'

          if name == 'Complex'
            class_loader.complex
            h = Hash[*o.children.map { |c| accept c }]
            register o, Complex(h['real'], h['image'])
          elsif name == 'Rational'
            class_loader.rational
            h = Hash[*o.children.map { |c| accept c }]
            register o, Rational(h['numerator'], h['denominator'])
          elsif name == 'Hash'
            revive_hash(register(o, {}), o)
          else
            obj = revive((resolve_class(name) || class_loader.object), o)
            obj
          end

        when /^!(?:str|ruby\/string)(?::(.*))?$/, 'tag:yaml.org,2002:str'
          klass   = resolve_class($1)
          members = {}
          string  = nil

          o.children.each_slice(2) do |k,v|
            key   = accept k
            value = accept v

            if key == 'str'
              if klass
                string = klass.allocate.replace value
              else
                string = value
              end
              register(o, string)
            else
              members[key] = value
            end
          end
          init_with(string, members.map { |k,v| [k.to_s.sub(/^@/, ''),v] }, o)
        when /^!ruby\/array:(.*)$/
          klass = resolve_class($1)
          list  = register(o, klass.allocate)

          members = Hash[o.children.map { |c| accept c }.each_slice(2).to_a]
          list.replace members['internal']

          members['ivars'].each do |ivar, v|
            list.instance_variable_set ivar, v
          end
          list

        when '!ruby/range'
          klass = class_loader.range
          h = Hash[*o.children.map { |c| accept c }]
          register o, klass.new(h['begin'], h['end'], h['excl'])

        when /^!ruby\/exception:?(.*)?$/
          h = Hash[*o.children.map { |c| accept c }]

          e = build_exception((resolve_class($1) || class_loader.exception),
                              h.delete('message'))

          e.set_backtrace h.delete('backtrace') if h.key? 'backtrace'
          init_with(e, h, o)

        when '!set', 'tag:yaml.org,2002:set'
          set = class_loader.psych_set.new
          @st[o.anchor] = set if o.anchor
          o.children.each_slice(2) do |k,v|
            set[accept(k)] = accept(v)
          end
          set

        when /^!ruby\/hash-with-ivars(?::(.*))?$/
          hash = $1 ? resolve_class($1).allocate : {}
          register o, hash
          o.children.each_slice(2) do |key, value|
            case key.value
            when 'elements'
              revive_hash hash, value
            when 'ivars'
              value.children.each_slice(2) do |k,v|
                hash.instance_variable_set accept(k), accept(v)
              end
            end
          end
          hash

        when /^!map:(.*)$/, /^!ruby\/hash:(.*)$/
          revive_hash register(o, resolve_class($1).allocate), o

        when '!omap', 'tag:yaml.org,2002:omap'
          map = register(o, class_loader.psych_omap.new)
          o.children.each_slice(2) do |l,r|
            map[accept(l)] = accept r
          end
          map

        when /^!ruby\/marshalable:(.*)$/
          name = $1
          klass = resolve_class(name)
          obj = register(o, klass.allocate)

          if obj.respond_to?(:init_with)
            init_with(obj, revive_hash({}, o), o)
          elsif obj.respond_to?(:marshal_load)
            marshal_data = o.children.map(&method(:accept))
            obj.marshal_load(marshal_data)
            obj
          else
            raise ArgumentError, "Cannot deserialize #{name}"
          end

        else
          revive_hash(register(o, {}), o)
        end
      end

      def visit_Psych_Nodes_Document o
        accept o.root
      end

      def visit_Psych_Nodes_Stream o
        o.children.map { |c| accept c }
      end

      def visit_Psych_Nodes_Alias o
        @st.fetch(o.anchor) { raise AnchorNotDefined, o.anchor }
      end

      private

      def register node, object
        @st[node.anchor] = object if node.anchor
        object
      end

      def register_empty object
        list = register(object, [])
        object.children.each { |c| list.push accept c }
        list
      end

      def revive_hash hash, o, tagged= false
        o.children.each_slice(2) { |k,v|
          key = accept(k)
          val = accept(v)

          if key == '<<' && k.tag != "tag:yaml.org,2002:str"
            case v
            when Nodes::Alias, Nodes::Mapping
              begin
                hash.merge! val
              rescue TypeError
                hash[key] = val
              end
            when Nodes::Sequence
              begin
                h = {}
                val.reverse_each do |value|
                  h.merge! value
                end
                hash.merge! h
              rescue TypeError
                hash[key] = val
              end
            else
              hash[key] = val
            end
          else
            if !tagged && @symbolize_names && key.is_a?(String)
              key = key.to_sym
            elsif !@freeze
              key = deduplicate(key)
            end

            hash[key] = val
          end

        }
        hash
      end

      if RUBY_VERSION < '2.7'
        def deduplicate key
          if key.is_a?(String)
            # It is important to untaint the string, otherwise it won't
            # be deduplicated into an fstring, but simply frozen.
            -(key.untaint)
          else
            key
          end
        end
      else
        def deduplicate key
          if key.is_a?(String)
            -key
          else
            key
          end
        end
      end

      def merge_key hash, key, val
      end

      def revive klass, node
        s = register(node, klass.allocate)
        init_with(s, revive_hash({}, node, true), node)
      end

      def init_with o, h, node
        c = Psych::Coder.new(node.tag)
        c.map = h

        if o.respond_to?(:init_with)
          o.init_with c
        else
          h.each { |k,v| o.instance_variable_set(:"@#{k}", v) }
        end
        o
      end

      # Convert +klassname+ to a Class
      def resolve_class klassname
        class_loader.load klassname
      end
    end

    class NoAliasRuby < ToRuby
      def visit_Psych_Nodes_Alias o
        raise AliasesNotEnabled
      end
    end
  end
end
