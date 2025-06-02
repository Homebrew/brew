module TypeProf
  class Type # or AbstractValue
    include Utils::StructuralEquality

    def initialize
      raise "cannot instantiate abstract type"
    end

    Builtin = {}

    def globalize(_env, _visited, _depth)
      self
    end

    def localize(env, _alloc_site, _depth)
      return env, self
    end

    def limit_size(limit)
      self
    end

    def self.match?(ty1, ty2)
      # both ty1 and ty2 should be global
      # ty1 is always concrete; it should not have type variables
      # ty2 might be abstract; it may have type variables
      case ty2
      when Type::Var
        { ty2 => ty1 }
      when Type::Any
        {}
      when Type::Union
        subst = nil
        ty2.each_child_global do |ty2|
          # this is very conservative to create subst:
          # Type.match?( int | str, int | X) creates { X => int | str } but should be { X => str }???
          subst2 = Type.match?(ty1, ty2)
          next unless subst2
          subst = Type.merge_substitution(subst, subst2)
        end
        subst
      else
        case ty1
        when Type::Var then raise "should not occur"
        when Type::Any
          subst = {}
          ty2.each_free_type_variable do |tyvar|
            subst[tyvar] = Type.any
          end
          subst
        when Type::Union
          subst = nil
          ty1.each_child_global do |ty1|
            subst2 = Type.match?(ty1, ty2)
            next unless subst2
            subst = Type.merge_substitution(subst, subst2)
          end
          subst
        else
          if ty2.is_a?(Type::ContainerType)
            # ty2 may have type variables
            return nil if ty1.class != ty2.class
            ty1.match?(ty2)
          elsif ty1.is_a?(Type::ContainerType)
            nil
          else
            ty1.consistent?(ty2) ? {} : nil
          end
        end
      end
    end

    def self.merge_substitution(subst1, subst2)
      if subst1
        subst1 = subst1.dup
        subst2.each do |tyvar, ty|
          if subst1[tyvar]
            subst1[tyvar] = subst1[tyvar].union(ty)
          else
            subst1[tyvar] = ty
          end
        end
        subst1
      else
        subst2
      end
    end

    def each_child
      yield self
    end

    def each_child_global
      yield self
    end

    def each_free_type_variable
    end

    def union(other)
      return self if self == other # fastpath

      ty1, ty2 = self, other

      case
      when ty1.is_a?(Union)
        ty1_types = ty1.types
        ty1_elems = ty1.elems
      when ty1.is_a?(Array) || ty1.is_a?(Hash)
        ty1_types = Utils::Set[]
        ty1_elems = {[ty1.class, ty1.base_type] => ty1.elems}
      else
        ty1_types = ty1_elems = nil
      end

      case
      when ty2.is_a?(Union)
        ty2_types = ty2.types
        ty2_elems = ty2.elems
      when ty2.is_a?(Array) || ty2.is_a?(Hash)
        ty2_types = Utils::Set[]
        ty2_elems = {[ty2.class, ty2.base_type] => ty2.elems}
      else
        ty2_types = ty2_elems = nil
      end

      if ty1_types && ty2_types
        ty = ty1_types.sum(ty2_types)
        all_elems = ty1_elems.dup || {}
        ty2_elems&.each do |key, elems|
          all_elems[key] = union_elems(all_elems[key], elems)
        end
        all_elems = nil if all_elems.empty?

        Type::Union.create(ty, all_elems)
      elsif ty1_types
        Type::Union.create(ty1_types.add(ty2), ty1_elems)
      elsif ty2_types
        Type::Union.create(ty2_types.add(ty1), ty2_elems)
      else
        Type::Union.create(Utils::Set[ty1, ty2], nil)
      end
    end

    private def union_elems(e1, e2)
      if e1
        if e2
          e1.union(e2)
        else
          e1
        end
      else
        e2
      end
    end

    def substitute(_subst, _depth)
      raise "cannot substitute abstract type: #{ self.class }"
    end

    def generate_substitution
      {}
    end

    DummySubstitution = Object.new
    def DummySubstitution.[](_)
      Type.any
    end

    def remove_type_vars
      substitute(DummySubstitution, Config.current.options[:type_depth_limit])
    end

    def include_untyped?(_scratch)
      false
    end

    class Any < Type
      def initialize
      end

      def inspect
        "Type::Any"
      end

      def screen_name(scratch)
        "untyped"
      end

      def method_dispatch_info
        nil
      end

      def consistent?(_other)
        raise "should not be called"
      end

      def substitute(_subst, _depth)
        self
      end

      def include_untyped?(_scratch)
        true
      end
    end

    class Void < Any
      def inspect
        "Type::Void"
      end

      def screen_name(scratch)
        "void"
      end
    end


    class Union < Type
      def self.create(tys, elems)
        if tys.size == 1 && !elems
          tys.each {|ty| return ty }
        elsif tys.size == 0
          if elems && elems.size == 1
            (container_kind, base_type), nelems = elems.first
            # container_kind = Type::Array or Type::Hash
            container_kind.new(nelems, base_type)
          else
            new(tys, elems)
          end
        else
          class_instances = []
          non_class_instances = []
          degenerated = false
          tys.each do |ty|
            if ty != Type::Instance.new(Type::Builtin[:nil]) && ty.is_a?(Type::Instance) && ty.klass.kind == :class
              class_instances << ty
              degenerated = true if ty.include_subclasses
            else
              non_class_instances << ty
            end
          end
          if (Config.current.options[:union_width_limit] >= 2 && class_instances.size >= Config.current.options[:union_width_limit]) || (degenerated && class_instances.size >= 2)
            create(Utils::Set[Instance.new_degenerate(class_instances), *non_class_instances], elems)
          else
            new(tys, elems)
          end
        end
      end

      def initialize(tys, elems)
        raise unless tys.is_a?(Utils::Set)
        @types = tys # Set

        # invariant check
        local = nil
        tys.each do |ty|
          raise ty.inspect unless ty.is_a?(Type)
          local = true if ty.is_a?(Local)
        end
        raise if local && elems

        @elems = elems
        raise elems.inspect if elems && !elems.is_a?(::Hash)
      end

      def each_free_type_variable(&blk)
        each_child_global do |ty|
          ty.each_free_type_variable(&blk)
        end
      end

      def limit_size(limit)
        return Type.any if limit <= 0
        tys = Utils::Set[]
        @types.each do |ty|
          tys = tys.add(ty.limit_size(limit - 1))
        end
        elems = @elems&.to_h do |key, elems|
          [key, elems.limit_size(limit - 1)]
        end
        Union.new(tys, elems)
      end

      attr_reader :types, :elems

      def each_child(&blk) # local
        @types.each(&blk)
        raise if @elems
      end

      def each_child_global(&blk)
        @types.each(&blk)
        @elems&.each do |(container_kind, base_type), elems|
          yield container_kind.new(elems, base_type)
        end
      end

      def inspect
        a = []
        a << "Type::Union{#{ @types.to_a.map {|ty| ty.inspect }.join(", ") }"
        @elems&.each do |(container_kind, base_type), elems|
          a << ", #{ container_kind.new(elems, base_type).inspect }"
        end
        a << "}"
        a.join
      end

      def screen_name(scratch)
        types = @types.to_a
        @elems&.each do |(container_kind, base_type), elems|
          types << container_kind.new(elems, base_type)
        end
        if types.size == 0
          "bot"
        else
          types = types.to_a
          optional = !!types.delete(Type::Instance.new(Type::Builtin[:nil]))
          bool = false
          if types.include?(Type::Instance.new(Type::Builtin[:false])) &&
             types.include?(Type::Instance.new(Type::Builtin[:true]))
            types.delete(Type::Instance.new(Type::Builtin[:false]))
            types.delete(Type::Instance.new(Type::Builtin[:true]))
            bool = true
          end
          types.delete(Type.any) unless Config.current.options[:show_untyped]
          proc_tys, types = types.partition {|ty| ty.is_a?(Proc) }
          types = types.map {|ty| ty.screen_name(scratch) }
          types << scratch.show_proc_signature(proc_tys) unless proc_tys.empty?
          types << "bool" if bool
          types = types.sort
          if optional
            case types.size
            when 0 then "nil"
            when 1 then types.first + "?"
            else
              "(#{ types.join (" | ") })?"
            end
          else
            types.join (" | ")
          end
        end
      end

      def globalize(env, visited, depth)
        return Type.any if depth <= 0
        tys = Utils::Set[]
        if @elems
          # XXX: If @elems is non nil, the Union type should global, so calling globalize against such a type should not occur.
          # However, currently, ActualArguments may contain global types for flag_args_kw_splat case.
          # This should be fixed in future in ActualArguments side. See Scratch#setup_actual_arguments.
          #raise
        end

        elems = @elems ? @elems.dup : {}
        @types.each do |ty|
          ty = ty.globalize(env, visited, depth - 1)
          case ty
          when Type::Array, Type::Hash
            key = [ty.class, ty.base_type]
            elems[key] = union_elems(elems[key], ty.elems)
          else
            tys = tys.add(ty)
          end
        end
        elems = nil if elems.empty?

        Type::Union.create(tys, elems)
      end

      def localize(env, alloc_site, depth)
        return env, Type.any if depth <= 0
        tys = @types.map do |ty|
          env, ty2 = ty.localize(env, alloc_site, depth - 1)
          ty2
        end
        @elems&.each do |(container_kind, base_type), elems|
          ty = container_kind.new(elems, base_type)
          env, ty = ty.localize(env, alloc_site, depth - 1)
          tys = tys.add(ty)
        end
        ty = Union.create(tys, nil)
        return env, ty
      end

      def consistent?(_other)
        raise "should not be called"
      end

      def substitute(subst, depth)
        return Type.any if depth <= 0
        unions = []
        tys = Utils::Set[]
        @types.each do |ty|
          ty = ty.substitute(subst, depth - 1)
          case ty
          when Union
            unions << ty
          else
            tys = tys.add(ty)
          end
        end
        elems = @elems&.to_h do |(container_kind, base_type), elems|
          [[container_kind, base_type], elems.substitute(subst, depth - 1)]
        end
        ty = Union.create(tys, elems)
        unions.each do |ty0|
          ty = ty.union(ty0)
        end
        ty
      end

      def include_untyped?(scratch)
        @types.each do |ty|
          return true if ty.include_untyped?(scratch)
        end
        @elems&.each do |(container_kind, base_type), elems|
          return true if base_type.include_untyped?(scratch)
          return true if elems.include_untyped?(scratch)
        end
        false
      end
    end

    def self.any
      Thread.current[:any] ||= Any.new
    end

    def self.bot
      Thread.current[:bot] ||= Union.new(Utils::Set[], nil)
    end

    def self.bool
      Thread.current[:bool] ||= Union.new(Utils::Set[
        Instance.new(Type::Builtin[:true]),
        Instance.new(Type::Builtin[:false])
      ], nil)
    end

    def self.nil
      Thread.current[:nil] ||= Instance.new(Type::Builtin[:nil])
    end

    def self.optional(ty)
      ty.union(Type.nil)
    end

    class Var < Type
      def initialize(name)
        @name = name
      end

      def screen_name(scratch)
        "Var[#{ @name }]"
      end

      def each_free_type_variable
        yield self
      end

      def substitute(subst, depth)
        if subst[self]
          subst[self].limit_size(depth)
        else
          self
        end
      end

      def consistent?(_other)
        raise "should not be called: #{ self }"
      end

      def add_subst!(ty, subst)
        if subst[self]
          subst[self] = subst[self].union(ty)
        else
          subst[self] = ty
        end
        true
      end
    end

    class Class < Type # or Module
      def initialize(kind, idx, type_params, superclass, name)
        @kind = kind # :class | :module
        @idx = idx
        @type_params = type_params
        @superclass = superclass
        raise if @kind == :class && !@superclass
        @_name = name
      end

      attr_reader :kind, :idx, :type_params, :superclass
      attr_accessor :superclass_type_args

      def inspect
        if @_name
          "#{ @_name }@#{ @idx }"
        else
          "Class[#{ @idx }]"
        end
      end

      def screen_name(scratch)
        "singleton(#{ scratch.get_class_name(self) })"
      end

      def method_dispatch_info
        [self, true, false]
      end

      def consistent?(other)
        case other
        when Type::Class
          ty = self
          loop do
            # ad-hoc
            return false if !ty || !other # module

            return true if ty.idx == other.idx
            return false if ty.idx == 0 # Object
            ty = ty.superclass
          end
        when Type::Instance
          return true if other.klass == Type::Builtin[:obj] || other.klass == Type::Builtin[:class] || other.klass == Type::Builtin[:module]
          return false
        else
          false
        end
      end

      def substitute(_subst, _depth)
        self
      end
    end

    class Instance < Type
      def initialize(klass, include_subclasses=false)
        raise unless klass
        raise if klass == Type.any
        raise if klass.is_a?(Type::Instance)
        raise if klass.is_a?(Type::Union)
        @klass = klass
        @include_subclasses = include_subclasses
      end

      def self.new_degenerate(instances)
        klass = instances.first.klass
        ancestors = []
        ancestor_idxs = {}
        while klass != :__root__
          ancestor_idxs[klass] = ancestors.size
          ancestors << klass
          klass = klass.superclass
        end
        common_superclass = nil
        instances[1..].each do |instance|
          klass = instance.klass
          while !ancestor_idxs[klass]
            klass = klass.superclass
          end
          common_superclass = klass
          ancestor_idxs[klass].times do |i|
            ancestor_idxs.delete(ancestors[i])
            ancestors[i] = nil
          end
        end
        new(common_superclass, true)
      end

      attr_reader :klass, :include_subclasses

      def inspect
        "I[#{ @klass.inspect }]"
      end

      def screen_name(scratch)
        case @klass
        when Type::Builtin[:nil] then "nil"
        when Type::Builtin[:true] then "true"
        when Type::Builtin[:false] then "false"
        else
          scratch.get_class_name(@klass) + (@include_subclasses ? "" : "")
        end
      end

      def method_dispatch_info
        [@klass, false, @include_subclasses]
      end

      def consistent?(other)
        case other
        when Type::Instance
          @klass.consistent?(other.klass)
        when Type::Class
          return true if @klass == Type::Builtin[:obj] || @klass == Type::Builtin[:class] || @klass == Type::Builtin[:module]
          return false
        else
          false
        end
      end

      def substitute(subst, depth)
        Instance.new(@klass.substitute(subst, depth))
      end
    end

    # This is an internal object in MRI, so a user program cannot create this object explicitly
    class ISeq < Type
      def initialize(iseq)
        @iseq = iseq
      end

      attr_reader :iseq

      def inspect
        "Type::ISeq[#{ @iseq }]"
      end

      def screen_name(_scratch)
        raise NotImplementedError
      end
    end

    class Proc < Type
      def initialize(block_body, base_type)
        @block_body, @base_type = block_body, base_type
      end

      attr_reader :block_body, :base_type

      def consistent?(other)
        case other
        when Type::Proc
          @block_body.consistent?(other.block_body)
        else
          self == other
        end
      end

      def method_dispatch_info
        @base_type.method_dispatch_info
      end

      def substitute(subst, depth)
        Proc.new(@block_body.substitute(subst, depth), @base_type)
      end

      def screen_name(scratch)
        scratch.show_proc_signature([self])
      end

      def include_untyped?(scratch)
        false # XXX: need to check the block signatures recursively
      end
    end

    class Symbol < Type
      def initialize(sym, base_type)
        @sym = sym
        @base_type = base_type
      end

      attr_reader :sym, :base_type

      def inspect
        "Type::Symbol[#{ @sym ? @sym.inspect : "(dynamic symbol)" }, #{ @base_type.inspect }]"
      end

      def consistent?(other)
        case other
        when Symbol
          @sym == other.sym
        else
          @base_type.consistent?(other)
        end
      end

      def screen_name(scratch)
        if @sym
          @sym.inspect
        else
          @base_type.screen_name(scratch)
        end
      end

      def method_dispatch_info
        @base_type.method_dispatch_info
      end

      def substitute(_subst, _depth)
        self # dummy
      end
    end

    # A local type
    class Literal < Type
      def initialize(lit, base_type)
        @lit = lit
        @base_type = base_type
      end

      attr_reader :lit, :base_type

      def inspect
        "Type::Literal[#{ @lit.inspect }, #{ @base_type.inspect }]"
      end

      def screen_name(scratch)
        @base_type.screen_name(scratch) + "<#{ @lit.inspect }>"
      end

      def globalize(_env, _visited, _depth)
        @base_type
      end

      def method_dispatch_info
        @base_type.method_dispatch_info
      end

      def consistent?(_other)
        raise "should not called"
      end
    end

    class HashGenerator
      def initialize
        @map_tys = {}
      end

      attr_reader :map_tys

      def []=(k_ty, v_ty)
        k_ty.each_child_global do |k_ty|
          # This is a temporal hack to mitigate type explosion
          k_ty = Type.any if k_ty.is_a?(Type::Array)
          k_ty = Type.any if k_ty.is_a?(Type::Hash)

          if @map_tys[k_ty]
            @map_tys[k_ty] = @map_tys[k_ty].union(v_ty)
          else
            @map_tys[k_ty] = v_ty
          end
        end
      end
    end

    def self.gen_hash(base_ty = Type::Instance.new(Type::Builtin[:hash]))
      hg = HashGenerator.new
      yield hg
      Type::Hash.new(Type::Hash::Elements.new(hg.map_tys), base_ty)
    end

    def self.guess_literal_type(obj)
      case obj
      when ::Symbol
        Type::Symbol.new(obj, Type::Instance.new(Type::Builtin[:sym]))
      when ::Integer
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:int]))
      when ::Rational
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:rational]))
      when ::Complex
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:complex]))
      when ::Float
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:float]))
      when ::Class
        return Type.any if obj < Exception
        case obj
        when ::Object
          Type::Builtin[:obj]
        when ::Array
          Type::Builtin[:ary]
        else
          raise "unknown class: #{ obj.inspect }"
        end
      when ::TrueClass
        Type::Instance.new(Type::Builtin[:true])
      when ::FalseClass
        Type::Instance.new(Type::Builtin[:false])
      when ::Array
        base_ty = Type::Instance.new(Type::Builtin[:ary])
        lead_tys = obj.map {|arg| guess_literal_type(arg) }
        Type::Array.new(Type::Array::Elements.new(lead_tys), base_ty)
      when ::Hash
        Type.gen_hash do |h|
          obj.each do |k, v|
            k_ty = guess_literal_type(k).globalize(nil, {}, Config.current.options[:type_depth_limit])
            v_ty = guess_literal_type(v)
            h[k_ty] = v_ty
          end
        end
      when ::String
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:str]))
      when ::Regexp
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:regexp]))
      when ::NilClass
        Type.nil
      when ::Range
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:range]))
      when ::Encoding
        Type::Literal.new(obj, Type::Instance.new(Type::Builtin[:encoding]))
      else
        raise "unknown object: #{ obj.inspect }"
      end
    end

    def self.builtin_global_variable_type(var)
      case var
      when :$_, :$/, :$\, :$,, :$;
        Type.optional(Type::Instance.new(Type::Builtin[:str]))
      when :$0, :$PROGRAM_NAME
        Type::Instance.new(Type::Builtin[:str])
      when :$~
        Type.optional(Type::Instance.new(Type::Builtin[:matchdata]))
      when :$., :$$
        Type::Instance.new(Type::Builtin[:int])
      when :$?
        Type.optional(Type::Instance.new(Type::Builtin[:int]))
      when :$!
        Type.optional(Type::Instance.new(Type::Builtin[:exc]))
      when :$@
        str = Type::Instance.new(Type::Builtin[:str])
        base_ty = Type::Instance.new(Type::Builtin[:ary])
        Type.optional(Type::Array.new(Type::Array::Elements.new([], str), base_ty))
      when :$*, :$:, :$LOAD_PATH, :$", :$LOADED_FEATURES
        str = Type::Instance.new(Type::Builtin[:str])
        base_ty = Type::Instance.new(Type::Builtin[:ary])
        Type::Array.new(Type::Array::Elements.new([], str), base_ty)
      when :$<
        :ARGF
      when :$>
        :STDOUT
      when :$DEBUG
        Type.bool
      when :$FILENAME
        Type::Instance.new(Type::Builtin[:str])
      when :$stdin
        :STDIN
      when :$stdout
        :STDOUT
      when :$stderr
        :STDERR
      when :$VERBOSE
        Type.bool.union(Type.nil)
      else
        nil
      end
    end
  end

  class Signature
    include Utils::StructuralEquality

    def screen_name(iseq, scratch)
      fargs_str = "("
      sig_help = {}
      add_farg = -> farg, name, help: false, key: sig_help.size do
        name = "`#{ name }`" if RBS::Parser::KEYWORDS.key?(name.to_s)
        name = "noname" if name.is_a?(Integer) || name == :"*"
        fargs_str << ", " if fargs_str != "("
        i = fargs_str.size
        fargs_str << (Config.current.options[:show_parameter_names] && name ? "#{ farg } #{ name }" : farg)
        sig_help[key] = (i...fargs_str.size)
      end

      @lead_tys.zip(iseq ? iseq.locals : []) do |ty, name|
        add_farg.call(ty.screen_name(scratch), name, help: true)
      end

      @opt_tys&.zip(iseq ? iseq.locals[@lead_tys.size, @opt_tys.size] : []) do |ty, name|
        add_farg.call("?" + ty.screen_name(scratch), name, help: true)
      end

      if @rest_ty
        if iseq
          rest_index = iseq.fargs_format[:rest_start]
          name = rest_index ? iseq.locals[rest_index] : nil
        end
        add_farg.call("*" + @rest_ty.screen_name(scratch), name)
      end

      if iseq
        post_start = iseq.fargs_format[:post_start]
        names = post_start ? iseq.locals[post_start, @post_tys.size] : []
      end
      @post_tys&.zip(names || []) do |ty, name|
        add_farg.call(ty.screen_name(scratch), name)
      end

      @kw_tys&.each do |req, sym, ty|
        opt = req ? "" : "?"
        add_farg.call("#{ opt }#{ sym }: #{ ty.screen_name(scratch) }", nil, help: true, key: sym)
      end

      if @kw_rest_ty
        all_val_ty = Type.bot
        @kw_rest_ty.each_child_global do |ty|
          if ty == Type.any
            val_ty = ty
          else
            # ty is a Type::Hash
            _key_ty, val_ty = ty.elems.squash
          end
          all_val_ty = all_val_ty.union(val_ty)
        end
        add_farg.call("**" + all_val_ty.screen_name(scratch), nil)
      end

      fargs_str << ")"

      fargs_str = "" if fargs_str == "()"

      # Dirty Hack: Stop the iteration at most once!
      # I'll remove this hack if RBS removes the limitation of nesting blocks
      return fargs_str, sig_help if caller_locations.any? {|frame| frame.label == "show_block_signature" }

      optional = false
      blks = []
      @blk_ty.each_child_global do |ty|
        if ty.is_a?(Type::Proc)
          blks << ty
        else
          # XXX: how should we handle types other than Type.nil
          optional = true
        end
      end
      if blks != []
        fargs_str << " " if fargs_str != ""
        fargs_str << "?" if optional
        fargs_str << scratch.show_block_signature(blks)
      end

      return fargs_str, sig_help
    end
  end

  class MethodSignature < Signature
    def initialize(lead_tys, opt_tys, rest_ty, post_tys, kw_tys, kw_rest_ty, blk_ty)
      @lead_tys = lead_tys
      @opt_tys = opt_tys
      raise unless opt_tys.is_a?(Array)
      @rest_ty = rest_ty
      @post_tys = post_tys
      raise unless post_tys
      @kw_tys = kw_tys
      kw_tys.each {|a| raise if a.size != 3 } if kw_tys
      @kw_rest_ty = kw_rest_ty
      kw_rest_ty&.each_child_global do |ty|
        raise ty.inspect if ty != Type.any && !ty.is_a?(Type::Hash)
      end
      @blk_ty = blk_ty
    end

    def include_untyped?(scratch)
      return true if @lead_tys.any? {|ty| ty.include_untyped?(scratch) }
      return true if @opt_tys.any? {|ty| ty.include_untyped?(scratch) }
      return true if @rest_ty&.include_untyped?(scratch)
      return true if @post_tys.any? {|ty| ty.include_untyped?(scratch) }
      return true if @kw_tys&.any? {|_, _, ty| ty.include_untyped?(scratch) }
      return true if @kw_rest_ty&.include_untyped?(scratch)
      return true if @blk_ty&.include_untyped?(scratch)
      false
    end

    attr_reader :lead_tys, :opt_tys, :rest_ty, :post_tys, :kw_tys, :kw_rest_ty, :blk_ty

    def substitute(subst, depth)
      lead_tys = @lead_tys.map {|ty| ty.substitute(subst, depth - 1) }
      opt_tys = @opt_tys.map {|ty| ty.substitute(subst, depth - 1) }
      rest_ty = @rest_ty&.substitute(subst, depth - 1)
      post_tys = @post_tys.map {|ty| ty.substitute(subst, depth - 1) }
      kw_tys = @kw_tys.map {|req, key, ty| [req, key, ty.substitute(subst, depth - 1)] }
      kw_rest_ty = @kw_rest_ty&.substitute(subst, depth - 1)
      blk_ty = @blk_ty.substitute(subst, depth - 1)
      MethodSignature.new(lead_tys, opt_tys, rest_ty, post_tys, kw_tys, kw_rest_ty, blk_ty)
    end

    def merge_as_block_arguments(other)
      lead_tys1, opt_tys1, rest_ty1, post_tys1 = @lead_tys, @opt_tys, @rest_ty, @post_tys
      lead_tys2, opt_tys2, rest_ty2, post_tys2 = other.lead_tys, other.opt_tys, other.rest_ty, other.post_tys

      case
      when lead_tys1.size > lead_tys2.size
        n = lead_tys2.size
        lead_tys1, opt_tys1 = lead_tys1[0, n], lead_tys1[n..] + opt_tys1
      when lead_tys1.size < lead_tys2.size
        n = lead_tys1.size
        lead_tys2, opt_tys2 = lead_tys2[0, n], lead_tys2[n..] + opt_tys2
      end
      case
      when post_tys1.size > post_tys2.size
        i = post_tys1.size - post_tys2.size
        if rest_ty1
          rest_ty1 = post_tys[0, i].inject(rest_ty1) {|ty1, ty2| ty1.union(ty2) }
          post_tys1 = post_tys1[i..]
        else
          opt_tys1, post_tys1 = opt_tys1 + post_tys1[0, i], post_tys1[i..]
        end
      when post_tys1.size < post_tys2.size
        i = post_tys2.size - post_tys1.size
        if rest_ty2
          rest_ty2 = post_tys[0, i].inject(rest_ty2) {|ty1, ty2| ty1.union(ty2) }
          post_tys2 = post_tys2[i..]
        else
          opt_tys2, post_tys2 = opt_tys2 + post_tys2[0, i], post_tys2[i..]
        end
      end

      # XXX: tweak keywords too

      msig1 = MethodSignature.new(lead_tys1, opt_tys1, rest_ty1, post_tys1, @kw_tys, @kw_rest_ty, @blk_ty)
      msig2 = MethodSignature.new(lead_tys2, opt_tys2, rest_ty2, post_tys2, other.kw_tys, other.kw_rest_ty, other.blk_ty)
      msig1.merge(msig2)
    end

    def merge(other)
      raise if @lead_tys.size != other.lead_tys.size
      raise if @post_tys.size != other.post_tys.size
      if @kw_tys && other.kw_tys
        kws1 = {}
        @kw_tys.each {|req, kw, _| kws1[kw] = req }
        kws2 = {}
        other.kw_tys.each {|req, kw, _| kws2[kw] = req }
        (kws1.keys & kws2.keys).each do |kw|
          raise if !!kws1[kw] != !!kws2[kw]
        end
      elsif @kw_tys || other.kw_tys
        (@kw_tys || other.kw_tys).each do |req,|
          raise if req
        end
      end
      lead_tys = @lead_tys.zip(other.lead_tys).map {|ty1, ty2| ty1.union(ty2) }
      if @opt_tys || other.opt_tys
        opt_tys = []
        [@opt_tys.size, other.opt_tys.size].max.times do |i|
          ty1 = @opt_tys[i]
          ty2 = other.opt_tys[i]
          ty = ty1 ? ty2 ? ty1.union(ty2) : ty1 : ty2
          opt_tys << ty
        end
      end
      if @rest_ty || other.rest_ty
        if @rest_ty && other.rest_ty
          rest_ty = @rest_ty.union(other.rest_ty)
        else
          rest_ty = @rest_ty || other.rest_ty
        end
      end
      post_tys = @post_tys.zip(other.post_tys).map {|ty1, ty2| ty1.union(ty2) }
      if @kw_tys && other.kw_tys
        kws1 = {}
        @kw_tys.each {|req, kw, ty| kws1[kw] = [req, ty] }
        kws2 = {}
        other.kw_tys.each {|req, kw, ty| kws2[kw] = [req, ty] }
        kw_tys = (kws1.keys | kws2.keys).map do |kw|
          req1, ty1 = kws1[kw]
          _req2, ty2 = kws2[kw]
          ty1 ||= Type.bot
          ty2 ||= Type.bot
          [!!req1, kw, ty1.union(ty2)]
        end
      elsif @kw_tys || other.kw_tys
        kw_tys = @kw_tys || other.kw_tys
      else
        kw_tys = nil
      end
      if @kw_rest_ty || other.kw_rest_ty
        if @kw_rest_ty && other.kw_rest_ty
          kw_rest_ty = @kw_rest_ty.union(other.kw_rest_ty)
        else
          kw_rest_ty = @kw_rest_ty || other.kw_rest_ty
        end
      end
      blk_ty = @blk_ty.union(other.blk_ty) if @blk_ty
      MethodSignature.new(lead_tys, opt_tys, rest_ty, post_tys, kw_tys, kw_rest_ty, blk_ty)
    end
  end

  class BlockSignature < Signature
    def initialize(lead_tys, opt_tys, rest_ty, blk_ty)
      @lead_tys = lead_tys
      @opt_tys = opt_tys
      @rest_ty = rest_ty
      @blk_ty = blk_ty
      # TODO: kw_tys
    end

    attr_reader :lead_tys, :opt_tys, :rest_ty, :blk_ty

    def merge(bsig)
      if @rest_ty && bsig.rest_ty
        rest_ty = @rest_ty.union(bsig.rest_ty)
        BlockSignature.new(@lead_tys, [], rest_ty, @blk_ty.union(bsig.blk_ty))
      elsif @rest_ty || bsig.rest_ty
        rest_ty = @rest_ty || bsig.rest_ty
        rest_ty = @opt_tys.inject(rest_ty, &:union)
        rest_ty = bsig.opt_tys.inject(rest_ty, &:union)

        lead_tys = []
        [@lead_tys.size, bsig.lead_tys.size].max.times do |i|
          ty1 = @lead_tys[i]
          ty2 = bsig.lead_tys[i]
          if ty1 && ty2
            lead_tys << ty1.union(ty2)
          else
            rest_ty = rest_ty.union(ty1 || ty2)
          end
        end

        BlockSignature.new(lead_tys, [], rest_ty, @blk_ty.union(bsig.blk_ty))
      else
        lead_tys = []
        n = [@lead_tys.size, bsig.lead_tys.size].min
        n.times do |i|
          lead_tys << @lead_tys[i].union(bsig.lead_tys[i])
        end
        opt_tys1 = @lead_tys[n..] + @opt_tys
        opt_tys2 = bsig.lead_tys[n..] + bsig.opt_tys
        opt_tys = []
        [opt_tys1.size, opt_tys2.size].max.times do |i|
          if opt_tys1[i] && opt_tys2[i]
            opt_tys << opt_tys1[i].union(opt_tys2[i])
          else
            opt_tys << (opt_tys1[i] || opt_tys2[i])
          end
        end
        BlockSignature.new(lead_tys, opt_tys, nil, @blk_ty.union(bsig.blk_ty))
      end
    end
  end
end
