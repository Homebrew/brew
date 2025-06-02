module TypeProf
  class AllocationSite
    include Utils::StructuralEquality

    def initialize(val, parent = nil)
      raise if !val.is_a?(Utils::StructuralEquality) && !val.is_a?(Integer) && !val.is_a?(Symbol)
      @val = val
      @parent = parent
    end

    attr_reader :val, :parent

    def add_id(val)
      AllocationSite.new(val, self)
    end
  end

  class Type # or AbstractValue
    # Cell, Array, and Hash are types for global interface, e.g., TypedISeq.
    # Do not push such types to local environment, stack, etc.

    class ContainerType < Type
      def match?(other)
        return nil if self.class != other.class
        return nil unless @base_type.consistent?(other.base_type)
        @elems.match?(other.elems)
      end

      def each_free_type_variable(&blk)
        @elems.each_free_type_variable(&blk)
      end

      def consistent?(other)
        raise "must not be used"
      end

      def self.create_empty_instance(klass)
        base_type = Type::Instance.new(klass)
        case klass
        when Type::Builtin[:ary] # XXX: check inheritance...
          Type::Array.new(Type::Array::Elements.new([], Type.bot), base_type)
        when Type::Builtin[:hash]
          Type.gen_hash(base_type) {|h| }
        else
          Type::Cell.new(Type::Cell::Elements.new([Type.bot] * klass.type_params.size), base_type)
        end
      end

      def include_untyped?(scratch)
        return true if @base_type.include_untyped?(scratch)
        return true if @elems.include_untyped?(scratch)
        false
      end
    end

    # The most basic container type for default type parameter class
    class Cell < ContainerType
      def initialize(elems, base_type)
        raise if !elems.is_a?(Cell::Elements)
        @elems = elems # Cell::Elements
        raise unless base_type
        @base_type = base_type
        if base_type.klass.type_params.size != elems.elems.size
          raise
        end
      end

      attr_reader :elems, :base_type

      def inspect
        "Type::Cell[#{ @elems.inspect }, base_type: #{ @base_type.inspect }]"
      end

      def screen_name(scratch)
        str = @elems.screen_name(scratch)
        if str.start_with?("*")
          str = @base_type.screen_name(scratch) + str[1..]
        end
        str
      end

      def localize(env, alloc_site, depth)
        return env, Type.any if depth <= 0
        alloc_site = alloc_site.add_id(:cell).add_id(@base_type)
        env, elems = @elems.localize(env, alloc_site, depth)
        ty = Local.new(Cell, alloc_site, @base_type)
        env = env.deploy_type(alloc_site, elems)
        return env, ty
      end

      def limit_size(limit)
        return Type.any if limit <= 0
        Cell.new(@elems.limit_size(limit - 1), @base_type)
      end

      def method_dispatch_info
        raise
      end

      def substitute(subst, depth)
        return Type.any if depth <= 0
        elems = @elems.substitute(subst, depth)
        Cell.new(elems, @base_type)
      end

      def generate_substitution
        subst = {}
        tyvars = @base_type.klass.type_params.map {|name,| Type::Var.new(name) }
        tyvars.zip(@elems.elems) do |tyvar, elem|
          if subst[tyvar]
            subst[tyvar] = subst[tyvar].union(elem)
          else
            subst[tyvar] = elem
          end
        end
        subst
      end

      class Elements # Cell
        include Utils::StructuralEquality

        def initialize(elems)
          @elems = elems
        end

        def self.dummy_elements
          Elements.new([]) # XXX
        end

        attr_reader :elems

        def to_local_type(id, base_ty)
          Type::Local.new(Cell, id, base_ty)
        end

        def globalize(env, visited, depth)
          Elements.new(@elems.map {|ty| ty.globalize(env, visited, depth) })
        end

        def localize(env, alloc_site, depth)
          elems = @elems.map.with_index do |ty, i|
            alloc_site2 = alloc_site.add_id(i)
            env, ty = ty.localize(env, alloc_site2, depth)
            ty
          end
          return env, Elements.new(elems)
        end

        def limit_size(limit)
          Elements.new(@elems.map {|ty| ty.limit_size(limit) })
        end

        def screen_name(scratch)
          "*[#{ @elems.map {|ty| ty.screen_name(scratch) }.join(", ") }]"
        end

        def pretty_print(q)
          q.group(9, "Elements[", "]") do
            q.seplist(@elems) do |elem|
              q.pp elem
            end
          end
        end

        def match?(other)
          return nil if @elems.size != other.elems.size
          subst = nil
          @elems.zip(other.elems) do |ty0, ty1|
            subst2 = Type.match?(ty0, ty1)
            return nil unless subst2
            subst = Type.merge_substitution(subst, subst2)
          end
          subst
        end

        def each_free_type_variable(&blk)
          @elems.each do |ty|
            ty.each_free_type_variable(&blk)
          end
        end

        def substitute(subst, depth)
          Elements.new(@elems.map {|ty| ty.substitute(subst, depth) })
        end

        def [](idx)
          @elems[idx]
        end

        def update(idx, ty)
          Elements.new(Utils.array_update(@elems, idx, @elems[idx].union(ty)))
        end

        def union(other)
          return self if self == other
          if @elems.size != other.elems.size
            raise "#{ @elems.size } != #{ other.elems.size }"
          end
          elems = []
          @elems.zip(other.elems) do |ty0, ty1|
            elems << ty0.union(ty1)
          end
          Elements.new(elems)
        end

        def include_untyped?(scratch)
          return @elems.any? {|ty| ty.include_untyped?(scratch) }
        end
      end
    end

    # Do not insert Array type to local environment, stack, etc.
    class Array < ContainerType
      def initialize(elems, base_type)
        raise unless elems.is_a?(Array::Elements)
        @elems = elems # Array::Elements
        raise unless base_type
        @base_type = base_type
      end

      attr_reader :elems, :base_type

      def inspect
        "Type::Array[#{ @elems.inspect }, base_type: #{ @base_type.inspect }]"
        #@base_type.inspect
      end

      def screen_name(scratch)
        str = @elems.screen_name(scratch)
        if str =~ /\A\*\[(.*)\]\z/
          str = @base_type.klass.type_params.map {|var_name,| var_name == :Elem ? $1 : "untyped" }.join(", ")
          str = "#{ @base_type.screen_name(scratch) }[#{ str }]"
        end
        str
      end

      def localize(env, alloc_site, depth)
        return env, Type.any if depth <= 0
        alloc_site = alloc_site.add_id(:ary).add_id(@base_type)
        env, elems = @elems.localize(env, alloc_site, depth - 1)
        ty = Local.new(Array, alloc_site, @base_type)
        env = env.deploy_type(alloc_site, elems)
        return env, ty
      end

      def limit_size(limit)
        return Type.any if limit <= 0
        Array.new(@elems.limit_size(limit - 1), @base_type)
      end

      def method_dispatch_info
        raise
      end

      def substitute(subst, depth)
        return Type.any if depth <= 0
        elems = @elems.substitute(subst, depth - 1)
        Array.new(elems, @base_type)
      end

      def generate_substitution
        { Type::Var.new(:Elem) => @elems.squash }
      end

      class Elements # Array
        include Utils::StructuralEquality

        def initialize(lead_tys, rest_ty = Type.bot)
          raise unless lead_tys.all? {|ty| ty.is_a?(Type) }
          raise unless rest_ty.is_a?(Type)
          @lead_tys, @rest_ty = lead_tys, rest_ty
        end

        def self.dummy_elements
          Elements.new([], Type.any)
        end

        attr_reader :lead_tys, :rest_ty

        def to_local_type(id, base_ty)
          Type::Local.new(Array, id, base_ty)
        end

        def globalize(env, visited, depth)
          lead_tys = []
          @lead_tys.each do |ty|
            lead_tys << ty.globalize(env, visited, depth)
          end
          rest_ty = @rest_ty&.globalize(env, visited, depth)
          Elements.new(lead_tys, rest_ty)
        end

        def localize(env, alloc_site, depth)
          lead_tys = @lead_tys.map.with_index do |ty, i|
            alloc_site2 = alloc_site.add_id(i)
            env, ty = ty.localize(env, alloc_site2, depth)
            ty
          end
          alloc_site_rest = alloc_site.add_id(:rest)
          env, rest_ty = @rest_ty.localize(env, alloc_site_rest, depth)
          return env, Elements.new(lead_tys, rest_ty)
        end

        def limit_size(limit)
          Elements.new(@lead_tys.map {|ty| ty.limit_size(limit) }, @rest_ty.limit_size(limit))
        end

        def screen_name(scratch)
          if @rest_ty == Type.bot
            if @lead_tys.empty?
              # This is heuristic: in general, an empty array is a wrong guess.
              # Note that an empty array is representable as "[ ]" in RBS, but
              # users often have to modify it to "Array[something]".
              # In this term, "Array[untyped]" is considered more useful than "[ ]".
              return "Array[untyped]"
            end
            s = @lead_tys.map do |ty|
              ty.screen_name(scratch)
            end
            s << "*" + @rest_ty.screen_name(scratch) if @rest_ty != Type.bot
            return "[#{ s.join(", ") }]"
          end

          "*[#{ squash.screen_name(scratch) }]"
        rescue SystemStackError
          p squash
          exit!
        end

        def pretty_print(q)
          q.group(9, "Elements[", "]") do
            q.seplist(@lead_tys + [@rest_ty]) do |elem|
              q.pp elem
            end
          end
        end

        def match?(other)
          n = [@lead_tys.size, other.lead_tys.size].min
          rest_ty1 = @lead_tys[n..].inject(@rest_ty) {|ty1, ty2| ty1.union(ty2) }
          rest_ty2 = other.lead_tys[n..].inject(other.rest_ty) {|ty1, ty2| ty1.union(ty2) }
          subst = nil
          (@lead_tys[0, n] + [rest_ty1]).zip(other.lead_tys[0, n] + [rest_ty2]) do |ty0, ty1|
            subst2 = Type.match?(ty0, ty1)
            return nil unless subst2
            subst = Type.merge_substitution(subst, subst2)
          end
          subst
        end

        def each_free_type_variable(&blk)
          @lead_tys.each do |ty|
            ty.each_free_type_variable(&blk)
          end
          @rest_ty&.each_free_type_variable(&blk)
        end

        def substitute(subst, depth)
          lead_tys = @lead_tys.map {|ty| ty.substitute(subst, depth) }
          rest_ty = @rest_ty.substitute(subst, depth)
          Elements.new(lead_tys, rest_ty)
        end

        def squash
          @lead_tys.inject(@rest_ty) {|ty1, ty2| ty1.union(ty2) } #.union(Type.nil) # is this needed?
        end

        def squash_or_any
          ty = squash
          ty == Type.bot ? Type.any : ty
        end

        def [](idx)
          if idx.is_a?(Range)
            if @rest_ty == Type.bot
              lead_tys = @lead_tys[idx]
              if lead_tys
                rest_ty = Type.bot
              else
                return Type.nil
              end
            else
              b, e = idx.begin, idx.end
              b = 0 if !b
              if !e
                lead_tys = @lead_tys[idx] || []
                rest_ty = @rest_ty
              elsif b >= 0
                if e >= 0
                  if b <= e
                    if e < @lead_tys.size
                      lead_tys = @lead_tys[idx]
                      rest_ty = Type.bot
                    else
                      lead_tys = @lead_tys[idx] || []
                      rest_ty = @rest_ty
                    end
                  else
                    return Type.nil
                  end
                else
                  lead_tys = @lead_tys[idx] || []
                  e = idx.exclude_end? ? e : e == -1 ? @lead_tys.size : e + 1
                  rest_ty = (@lead_tys[e + 1..] || []).inject(@rest_ty) {|ty0, ty1| ty0.union(ty1) }
                end
              else
                lead_tys = []
                if e >= 0
                  rest_ty = e < @lead_tys.size ? Type.bot : @rest_ty
                  range = [0, @lead_tys.size + b].max .. (idx.exclude_end? ? e - 1 : e)
                  rest_ty = @lead_tys[range].inject(rest_ty) {|ty0, ty1| ty0.union(ty1) }
                else
                  if b <= e
                    range = [0, @lead_tys.size + b].max .. (idx.exclude_end? ? e - 1 : e)
                    rest_ty = @lead_tys[range].inject(@rest_ty) {|ty0, ty1| ty0.union(ty1) }
                  else
                    return Type.nil
                  end
                end
              end
            end
            base_ty = Type::Instance.new(Type::Builtin[:ary])
            Array.new(Elements.new(lead_tys, rest_ty), base_ty)
          elsif idx >= 0
            if idx < @lead_tys.size
              @lead_tys[idx]
            elsif @rest_ty == Type.bot
              Type.nil
            else
              @rest_ty
            end
          else
            i = @lead_tys.size + idx
            i = [i, 0].max
            ty = @rest_ty
            @lead_tys[i..].each do |ty2|
              ty = ty.union(ty2)
            end
            ty
          end
        end

        def update(idx, ty)
          if idx
            if idx >= 0
              if idx < @lead_tys.size
                lead_tys = Utils.array_update(@lead_tys, idx, ty)
                Elements.new(lead_tys, @rest_ty)
              else
                rest_ty = @rest_ty.union(ty)
                Elements.new(@lead_tys, rest_ty)
              end
            else
              i = @lead_tys.size + idx
              if @rest_ty == Type.bot
                if i >= 0
                  lead_tys = Utils.array_update(@lead_tys, i, ty)
                  Elements.new(lead_tys, Type.bot)
                else
                  # TODO: out of bound? should we emit an error?
                  Elements.new(@lead_tys, Type.bot)
                end
              else
                i = [i, 0].max
                lead_tys = @lead_tys[0, i] + @lead_tys[i..].map {|ty2| ty2.union(ty) }
                rest_ty = @rest_ty.union(ty)
                Elements.new(@lead_tys, rest_ty)
              end
            end
          else
            lead_tys = @lead_tys.map {|ty1| ty1.union(ty) }
            rest_ty = @rest_ty.union(ty)
            Elements.new(lead_tys, rest_ty)
          end
        end

        def append(ty)
          if @rest_ty == Type.bot
            if @lead_tys.size < 5 # XXX: should be configurable, or ...?
              lead_tys = @lead_tys + [ty]
              Elements.new(lead_tys, @rest_ty)
            else
              Elements.new(@lead_tys, ty)
            end
          else
            Elements.new(@lead_tys, @rest_ty.union(ty))
          end
        end

        def union(other)
          return self if self == other
          raise "Hash::Elements merge Array::Elements" if other.is_a?(Hash::Elements)

          lead_count = [@lead_tys.size, other.lead_tys.size].min
          lead_tys = (0...lead_count).map do |i|
            @lead_tys[i].union(other.lead_tys[i])
          end

          rest_ty = @rest_ty.union(other.rest_ty)
          (@lead_tys[lead_count..-1] + other.lead_tys[lead_count..-1]).each do |ty|
            rest_ty = rest_ty.union(ty)
          end

          Elements.new(lead_tys, rest_ty)
        end

        def take_first(num)
          base_ty = Type::Instance.new(Type::Builtin[:ary])
          if @lead_tys.size >= num
            lead_tys = @lead_tys[0, num]
            rest_ary_ty = Array.new(Elements.new(@lead_tys[num..-1], @rest_ty), base_ty)
            return lead_tys, rest_ary_ty
          else
            lead_tys = @lead_tys.dup
            until lead_tys.size == num
              # .union(Type.nil) is needed for `a, b, c = [42]` to assign nil to b and c
              lead_tys << @rest_ty.union(Type.nil)
            end
            rest_ary_ty = Array.new(Elements.new([], @rest_ty), base_ty)
            return lead_tys, rest_ary_ty
          end
        end

        def take_last(num)
          base_ty = Type::Instance.new(Type::Builtin[:ary])
          if @rest_ty == Type.bot
            if @lead_tys.size >= num
              following_tys = @lead_tys[-num, num]
              rest_ary_ty = Array.new(Elements.new(@lead_tys[0...-num], Type.bot), base_ty)
              return rest_ary_ty, following_tys
            else
              following_tys = @lead_tys[-num, num] || []
              until following_tys.size == num
                following_tys.unshift(Type.nil)
              end
              rest_ary_ty = Array.new(Elements.new([], Type.bot), base_ty)
              return rest_ary_ty, following_tys
            end
          else
            lead_tys = @lead_tys.dup
            last_ty = rest_ty
            following_tys = []
            until following_tys.size == num
              last_ty = last_ty.union(lead_tys.pop) unless lead_tys.empty?
              following_tys.unshift(last_ty)
            end
            rest_ty = lead_tys.inject(last_ty) {|ty1, ty2| ty1.union(ty2) }
            rest_ary_ty = Array.new(Elements.new([], rest_ty), base_ty)
            return rest_ary_ty, following_tys
          end
        end

        def include_untyped?(scratch)
          return true if @lead_tys.any? {|ty| ty.include_untyped?(scratch) }
          return true if @rest_ty.include_untyped?(scratch)
          false
        end
      end
    end

    class Hash < ContainerType
      def initialize(elems, base_type)
        @elems = elems
        raise unless elems
        @base_type = base_type
      end

      attr_reader :elems, :base_type

      def inspect
        "Type::Hash#{ @elems.inspect }"
      end

      def screen_name(scratch)
        @elems.screen_name(scratch)
      end

      def localize(env, alloc_site, depth)
        return env, Type.any if depth <= 0
        alloc_site = alloc_site.add_id(:hash).add_id(@base_type)
        env, elems = @elems.localize(env, alloc_site, depth - 1)
        ty = Local.new(Hash, alloc_site, @base_type)
        env = env.deploy_type(alloc_site, elems)
        return env, ty
      end

      def limit_size(limit)
        return Type.any if limit <= 0
        Hash.new(@elems.limit_size(limit - 1), @base_type)
      end

      def method_dispatch_info
        raise
      end

      def substitute(subst, depth)
        return Type.any if depth <= 0
        elems = @elems.substitute(subst, depth - 1)
        Hash.new(elems, @base_type)
      end

      def generate_substitution
        tyvar_k = Type::Var.new(:K)
        tyvar_v = Type::Var.new(:V)
        k_ty0, v_ty0 = @elems.squash
        # XXX: need to heuristically replace ret type Hash[K, V] with self, instead of conversative type?
        { tyvar_k => k_ty0, tyvar_v => v_ty0 }
      end

      class Elements # Hash
        include Utils::StructuralEquality

        def initialize(map_tys)
          map_tys.each do |k_ty, v_ty|
            raise unless k_ty.is_a?(Type)
            raise unless v_ty.is_a?(Type)
            raise if k_ty.is_a?(Type::Union)
            raise if k_ty.is_a?(Type::Local)
            raise if k_ty.is_a?(Type::Array)
            raise if k_ty.is_a?(Type::Hash)
          end
          @map_tys = map_tys
        end

        def self.dummy_elements
          Elements.new({Type.any => Type.any})
        end

        attr_reader :map_tys

        def to_local_type(id, base_ty)
          Type::Local.new(Hash, id, base_ty)
        end

        def globalize(env, visited, depth)
          map_tys = {}
          @map_tys.each do |k_ty, v_ty|
            v_ty = v_ty.globalize(env, visited, depth)
            if map_tys[k_ty]
              map_tys[k_ty] = map_tys[k_ty].union(v_ty)
            else
              map_tys[k_ty] = v_ty
            end
          end
          Elements.new(map_tys)
        end

        def localize(env, alloc_site, depth)
          map_tys = @map_tys.to_h do |k_ty, v_ty|
            alloc_site2 = alloc_site.add_id(k_ty)
            env, v_ty = v_ty.localize(env, alloc_site2, depth)
            [k_ty, v_ty]
          end
          return env, Elements.new(map_tys)
        end

        def limit_size(limit)
          map_tys = {}
          @map_tys.each do |k_ty, v_ty|
            k_ty = k_ty.limit_size(limit)
            v_ty = v_ty.limit_size(limit)
            if map_tys[k_ty]
              map_tys[k_ty] = map_tys[k_ty].union(v_ty)
            else
              map_tys[k_ty] = v_ty
            end
          end
          Elements.new(map_tys)
        end

        def screen_name(scratch)
          if !@map_tys.empty? && @map_tys.all? {|k_ty,| k_ty.is_a?(Type::Symbol) }
            s = @map_tys.map do |k_ty, v_ty|
              v = v_ty.screen_name(scratch)
              "#{ k_ty.sym }: #{ v }"
            end.join(", ")
            "{#{ s }}"
          else
            k_ty = v_ty = Type.bot
            @map_tys.each do |k, v|
              k_ty = k_ty.union(k)
              v_ty = v_ty.union(v)
            end
            k_ty = Type.any if k_ty == Type.bot
            v_ty = Type.any if v_ty == Type.bot
            k_ty = k_ty.screen_name(scratch)
            v_ty = v_ty.screen_name(scratch)
            "Hash[#{ k_ty }, #{ v_ty }]"
          end
        end

        def pretty_print(q)
          q.group(9, "Elements[", "]") do
            q.seplist(@map_tys) do |k_ty, v_ty|
              q.group do
                q.pp k_ty
                q.text '=>'
                q.group(1) do
                  q.breakable ''
                  q.pp v_ty
                end
              end
            end
          end
        end

        def match?(other)
          subst = nil
          other.map_tys.each do |k1, v1|
            subst2 = nil
            @map_tys.each do |k0, v0|
              subst3 = Type.match?(k0, k1)
              if subst3
                subst4 = Type.match?(v0, v1)
                if subst4
                  subst2 = Type.merge_substitution(subst2, subst3)
                  subst2 = Type.merge_substitution(subst2, subst4)
                end
              end
            end
            return nil unless subst2
            subst = Type.merge_substitution(subst, subst2)
          end
          subst
        end

        def each_free_type_variable(&blk)
          @map_tys.each do |k, v|
            k.each_free_type_variable(&blk)
            v.each_free_type_variable(&blk)
          end
        end

        def substitute(subst, depth)
          map_tys = {}
          @map_tys.each do |k_ty_orig, v_ty_orig|
            k_ty = k_ty_orig.substitute(subst, depth)
            v_ty = v_ty_orig.substitute(subst, depth)
            k_ty.each_child_global do |k_ty|
              # This is a temporal hack to mitigate type explosion
              k_ty = Type.any if k_ty.is_a?(Type::Array)
              k_ty = Type.any if k_ty.is_a?(Type::Hash)
              if map_tys[k_ty]
                map_tys[k_ty] = map_tys[k_ty].union(v_ty)
              else
                map_tys[k_ty] = v_ty
              end
            end
          end
          Elements.new(map_tys)
        end

        def squash
          all_k_ty, all_v_ty = Type.bot, Type.bot
          @map_tys.each do |k_ty, v_ty|
            all_k_ty = all_k_ty.union(k_ty)
            all_v_ty = all_v_ty.union(v_ty)
          end
          return all_k_ty, all_v_ty
        end

        def [](key_ty)
          val_ty = Type.bot
          @map_tys.each do |k_ty, v_ty|
            if Type.match?(k_ty, key_ty)
              val_ty = val_ty.union(v_ty)
            end
          end
          val_ty
        end

        def update(idx, ty)
          map_tys = @map_tys.dup
          idx.each_child_global do |idx|
            # This is a temporal hack to mitigate type explosion
            idx = Type.any if idx.is_a?(Type::Array)
            idx = Type.any if idx.is_a?(Type::Hash)

            if map_tys[idx]
              map_tys[idx] = map_tys[idx].union(ty)
            else
              map_tys[idx] = ty
            end
          end
          Elements.new(map_tys)
        end

        def union(other)
          return self if self == other
          raise "Array::Elements merge Hash::Elements" if other.is_a?(Array::Elements)

          map_tys = @map_tys.dup
          other.map_tys.each do |k_ty, v_ty|
            if map_tys[k_ty]
              map_tys[k_ty] = map_tys[k_ty].union(v_ty)
            else
              map_tys[k_ty] = v_ty
            end
          end

          Elements.new(map_tys)
        end

        def to_keywords
          kw_tys = {}
          @map_tys.each do |key_ty, val_ty|
            if key_ty.is_a?(Type::Symbol)
              kw_tys[key_ty.sym] = val_ty
            else
              all_val_ty = Type.bot
              @map_tys.each do |_key_ty, val_ty|
                all_val_ty = all_val_ty.union(val_ty)
              end
              return { nil => all_val_ty }
            end
          end
          kw_tys
        end

        def include_untyped?(scratch)
          @map_tys.each do |key, val|
            return true if key.include_untyped?(scratch)
            return true if val.include_untyped?(scratch)
          end
          false
        end
      end
    end

    class Local < ContainerType
      def initialize(kind, id, base_type)
        @kind = kind
        raise if @kind != Cell && @kind != Array && @kind != Hash
        @id = id
        raise unless base_type
        @base_type = base_type
      end

      attr_reader :kind, :id, :base_type

      def inspect
        "Type::Local[#{ @kind }, #{ @id }, base_type: #{ @base_type.inspect }]"
      end

      def screen_name(scratch)
        #raise "Local type must not be included in signature"
        "Local[#{ @kind }]"
      end

      def globalize(env, visited, depth)
        if visited[self] || depth <= 0
          Type.any
        else
          visited[self] = true
          elems = env.get_container_elem_types(@id)
          if elems
            elems = elems.globalize(env, visited, depth - 1)
          else
            # TODO: currently out-of-scope array cannot be accessed
            elems = @kind::Elements.dummy_elements
          end
          visited.delete(self)
          @kind.new(elems, @base_type)
        end
      end

      def method_dispatch_info
        @base_type.method_dispatch_info
      end

      def update_container_elem_type(subst, env, caller_ep, scratch)
        case
        when @kind == Cell
          tyvars = @base_type.klass.type_params.map {|name,| Type::Var.new(name) }
          # XXX: This should be skipped when the called methods belongs to superclass
          tyvars.each_with_index do |tyvar, idx|
            ty = subst[tyvar]
            if ty
              env, ty = scratch.localize_type(ty, env, caller_ep)
              env = scratch.update_container_elem_types(env, caller_ep, @id, @base_type) do |elems|
                elems.update(idx, ty)
              end
            end
          end
        when @kind == Array
          tyvar_elem = Type::Var.new(:Elem)
          if subst[tyvar_elem]
            ty = subst[tyvar_elem]
            env, ty = scratch.localize_type(ty, env, caller_ep)
            env = scratch.update_container_elem_types(env, caller_ep, @id, @base_type) do |elems|
              elems.update(nil, ty)
            end
          end
        when @kind == Hash
          tyvar_k = Type::Var.new(:K)
          tyvar_v = Type::Var.new(:V)
          if subst[tyvar_k] && subst[tyvar_v]
            k_ty = subst[tyvar_k]
            v_ty = subst[tyvar_v]
            alloc_site = AllocationSite.new(caller_ep)
            env, k_ty = scratch.localize_type(k_ty, env, caller_ep, alloc_site.add_id(:k))
            env, v_ty = scratch.localize_type(v_ty, env, caller_ep, alloc_site.add_id(:v))
            env = scratch.update_container_elem_types(env, caller_ep, @id, @base_type) do |elems|
              elems.update(k_ty, v_ty)
            end
          end
        end
        env
      end
    end
  end
end
