module TypeProf
  # Arguments from caller side
  class ActualArguments
    def initialize(lead_tys, rest_ty, kw_tys, blk_ty)
      @lead_tys = lead_tys
      raise unless lead_tys
      @rest_ty = rest_ty
      @kw_tys = kw_tys # kw_tys should be {:key1 => Type, :key2 => Type, ...} or {nil => Type}
      raise if !kw_tys.is_a?(::Hash)
      @blk_ty = blk_ty
      raise unless blk_ty
    end

    def for_method_missing(mid)
      ActualArguments.new([mid] + @lead_tys, @rest_ty, @kw_tys, @blk_ty)
    end

    attr_reader :lead_tys, :rest_ty, :kw_tys, :blk_ty
    attr_accessor :node_id

    def globalize(caller_env, visited, depth)
      lead_tys = @lead_tys.map {|ty| ty.globalize(caller_env, visited, depth) }
      rest_ty = @rest_ty.globalize(caller_env, visited, depth) if @rest_ty
      kw_tys = @kw_tys.to_h do |key, ty|
        [key, ty.globalize(caller_env, visited, depth)]
      end
      ActualArguments.new(lead_tys, rest_ty, kw_tys, @blk_ty)
    end

    def limit_size(limit)
      self
    end

    def consistent_with_method_signature?(msig)
      aargs = @lead_tys.dup

      # aargs: lead_tys, rest_ty
      # msig: lead_tys, opt_tys, rest_ty, post_tys
      if @rest_ty
        lower_bound = [0, msig.lead_tys.size + msig.post_tys.size - aargs.size].max
        upper_bound = [0, lower_bound + msig.opt_tys.size].max
        (lower_bound..upper_bound).each do |n|
          # BUG: @rest_ty is an Array, so need to squash
          tmp_aargs = ActualArguments.new(@lead_tys + [@rest_ty] * n, nil, @kw_tys, @blk_ty)
          subst = tmp_aargs.consistent_with_method_signature?(msig) # XXX: wrong subst handling in the loop!
          return subst if subst
        end
        return nil
      end

      subst = {}
      if msig.rest_ty
        return nil if aargs.size < msig.lead_tys.size + msig.post_tys.size
        aargs.shift(msig.lead_tys.size).zip(msig.lead_tys) do |aarg, farg|
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
        aargs.pop(msig.post_tys.size).zip(msig.post_tys) do |aarg, farg|
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
        msig.opt_tys.each do |farg|
          break if aargs.empty?
          aarg = aargs.shift
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
        aargs.each do |aarg|
          return nil unless subst2 = Type.match?(aarg, msig.rest_ty)
          subst = Type.merge_substitution(subst, subst2)
        end
      else
        return nil if aargs.size < msig.lead_tys.size + msig.post_tys.size
        return nil if aargs.size > msig.lead_tys.size + msig.post_tys.size + msig.opt_tys.size
        aargs.shift(msig.lead_tys.size).zip(msig.lead_tys) do |aarg, farg|
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
        aargs.pop(msig.post_tys.size).zip(msig.post_tys) do |aarg, farg|
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
        aargs.zip(msig.opt_tys) do |aarg, farg|
          return nil unless subst2 = Type.match?(aarg, farg)
          subst = Type.merge_substitution(subst, subst2)
        end
      end
      # XXX: msig.keyword_tys

      case msig.blk_ty
      when Type::Proc
        return nil if @blk_ty == Type.nil
      when Type.nil
        return nil if @blk_ty != Type.nil
      when Type::Any
      else
        raise "unknown type of formal block signature"
      end

      subst
    end

    def argument_error(given, exp_lower, exp_upper)
      case
      when !exp_upper then exp = "#{ exp_lower }+"
      when exp_lower == exp_upper then exp = "#{ exp_lower }"
      else exp = "#{ exp_lower }..#{ exp_upper }"
      end
      "wrong number of arguments (given #{ given }, expected #{ exp })"
    end

    def to_block_signature
      if @rest_ty
        rest_ty = Type.bot
        @rest_ty.each_child_global do |ty|
          if ty.is_a?(Type::Array)
            rest_ty = rest_ty.union(ty.elems.squash)
          else
            # XXX: to_ary?
            rest_ty = rest_ty.union(ty)
          end
        end
      end
      BlockSignature.new(@lead_tys, [], rest_ty, @blk_ty)
    end

    def setup_formal_arguments(kind, locals, fargs_format)
      lead_num = fargs_format[:lead_num] || 0
      post_num = fargs_format[:post_num] || 0
      post_index = fargs_format[:post_start]
      rest_index = fargs_format[:rest_start]
      keyword = fargs_format[:keyword]
      kw_index = fargs_format[:kwbits] - keyword.size if keyword
      kwrest_index = fargs_format[:kwrest]
      block_index = fargs_format[:block_start]
      opt = fargs_format[:opt] || [0]
      ambiguous_param0 = fargs_format[:ambiguous_param0]

      lead_tys = @lead_tys
      rest_ty = @rest_ty

      if kind == :block
        # The rule of passing arguments to block:
        #
        # Let A is actual arguments and F is formal arguments.
        # If F is NOT ambiguous_param0, and if length(A) == 1, and if A[0] is an Array,
        # then replace A with A[0]. And then, F[i] = A[i] for all 0 <= i < length(F).

        # Handling the special case
        if !ambiguous_param0
          if lead_tys.size == 1 && !rest_ty && @kw_tys.empty? # length(A) == 1
            ty = lead_tys[0]
            case ty
            when Type::Array
              lead_tys = ty.elems.lead_tys
              rest_ty = ty.elems.rest_ty
            when Type::Union
              if ty.elems
                other_elems = {}
                ty.elems.each do |(container_kind, base_type), elems|
                  if container_kind == Type::Array
                    rest_ty = rest_ty ? rest_ty.union(elems.squash) : elems.squash
                  else
                    other_elems[[container_kind, base_type]] = elems
                  end
                end
              end
              lead_tys = [Type::Union.new(ty.types, other_elems)]
            end
          end
        end
      end

      # Normal case: copy actual args to formal args
      if rest_ty
        ty = Type.bot
        additional_lead_size = nil
        rest_ty.each_child_global do |ty0|
          if ty0.is_a?(Type::Array)
            additional_lead_size = [additional_lead_size, ty0.elems.lead_tys.size].compact.min
          else
            additional_lead_size = 0
          end
        end
        additional_lead_tys = [Type.bot] * (additional_lead_size || 0)
        rest_ty.each_child_global do |ty0|
          if ty0.is_a?(Type::Array)
            tys, new_rest_ty = ty0.elems.take_first(additional_lead_size)
            tys.each_with_index do |ty00, i|
              additional_lead_tys[i] = additional_lead_tys[i].union(ty00)
            end
            ty = ty.union(new_rest_ty.elems.squash)
          else
            # XXX: to_ary?
            ty = ty.union(ty0)
          end
        end
        lead_tys += additional_lead_tys
        rest_ty = ty

        # XXX: Strictly speaking, this is needed, but it brings false positives. Which is better?
        #rest_ty = rest_ty.union(Type.nil)

        if rest_index
          # foo(a0, a1, a2, ...(rest_ty)) -->
          #            def foo(l0, l1, o0=, o1=, *rest, p0, p1)
          # lead_ty argc == 0:  -   -   -    -      -    -   -
          # lead_ty argc == 1: a0   -   -    -      -    -   -
          # lead_ty argc == 2: a0  a1   -    -      -    -   -
          # lead_ty argc == 3: a0  a1   -    -      -   a2   -
          # lead_ty argc == 4: a0  a1   -    -      -   a2  a3
          # lead_ty argc == 5: a0  a1  a2    -      -   a3  a4
          # lead_ty argc == 6: a0  a1  a2   a3      -   a4  a5
          # lead_ty argc == 7: a0  a1  a2   a3    a4    a5  a6
          # lead_ty argc == 8: a0  a1  a2   a3    a4|a5 a6  a7
          #
          # l0   = a0
          # l1   = a1
          # o0   = a2
          # o1   = a3
          # rest = a4|a5|...|rest_ty (= cum_lead_tys[4])
          # p0   = a2|a3|...|rest_ty (= cum_lead_tys[2])
          # p1   = a3|a4|...|rest_ty (= cum_lead_tys[3])

          cum_lead_tys = []
          ty = rest_ty
          lead_tys.reverse_each do |ty0|
            cum_lead_tys.unshift(ty = ty.union(ty0))
          end

          # l1, l2, o1, o2
          (lead_num + opt.size - 1).times {|i| locals[i] = lead_tys[i] || rest_ty }
          opt_count = opt.size - 1

          # rest
          ty = cum_lead_tys[lead_num + opt.size - 1] || rest_ty
          locals[rest_index] = Type::Array.new(Type::Array::Elements.new([], ty), Type::Instance.new(Type::Builtin[:ary]))

          # p0, p1
          off = [lead_num, lead_tys.size - post_num].max
          post_num.times {|i| locals[post_index + i] = cum_lead_tys[off + i] || rest_ty }
        else
          # foo(a0, a1, a2, ...(rest_ty)) -->
          #            def foo(l0, l1, o0=, o1=, p0, p1)
          # lead_ty argc == 0:  -   -   -    -    -   -
          # lead_ty argc == 1: a0   -   -    -    -   -
          # lead_ty argc == 2: a0  a1   -    -    -   -
          # lead_ty argc == 3: a0  a1   -    -   a2   -
          # lead_ty argc == 4: a0  a1   -    -   a2  a3
          # lead_ty argc == 5: a0  a1  a2    -   a3  a4
          # lead_ty argc == 6: a0  a1  a2   a3   a4  a5
          # lead_ty argc == 7: a0  a1  a2   a3   a4  a5 (if there is a6, report error if kind is method, or ignore if kind is block)
          #
          # l0 = a0
          # l1 = a1
          # o0 = a2
          # o1 = a3
          # p0 = a2|a3|a4
          # p1 = a3|a4|a5

          if kind == :method && lead_num + opt.size - 1 + post_num < lead_tys.size
            return argument_error(lead_tys.size, lead_num + post_num, lead_num + post_num + opt.size - 1)
          end

          # l1, l2, o1, o2
          (lead_num + opt.size - 1).times {|i| locals[i] = lead_tys[i] || rest_ty }
          opt_count = opt.size - 1

          # p0, p1
          post_num.times do |i|
            candidates = lead_tys[lead_num, opt.size] || []
            candidates << rest_ty if candidates.size < opt.size
            locals[post_index + i] = candidates.inject(&:union)
          end
        end
      else
        if rest_index
          # foo(a0, a1, a2) -->
          #            def foo(l0, l1, o0=, o1=, *rest, p0, p1)
          # lead_ty argc == 0:  -   -   -    -      -    -   - (error if kind is method)
          # lead_ty argc == 1: a0   -   -    -      -    -   - (error if kind is method)
          # lead_ty argc == 2: a0  a1   -    -      -    -   - (error if kind is method)
          # lead_ty argc == 3: a0  a1   -    -      -   a2   - (error if kind is method)
          # lead_ty argc == 4: a0  a1   -    -      -   a2  a3
          # lead_ty argc == 5: a0  a1  a2    -      -   a3  a4
          # lead_ty argc == 6: a0  a1  a2   a3      -   a4  a5
          # lead_ty argc == 7: a0  a1  a2   a3    a4    a5  a6
          # lead_ty argc == 8: a0  a1  a2   a3    a4|a5 a6  a7
          #
          # len(a) < 4 -> error
          #
          # l0   = a0
          # l1   = a1
          # o0   = a2
          # o1   = a3
          # rest = a4|a5|...|a[[4,len(a)-3].max]
          # p0   = a[[2,len(a)-2].max]
          # p1   = a[[3,len(a)-1].max]

          if kind == :method && lead_tys.size < lead_num + post_num
            return argument_error(lead_tys.size, lead_num + post_num, nil)
          end

          # l0, l1
          lead_num.times {|i| locals[i] = lead_tys[i] || Type.nil }

          # o0, o1
          opt_count = (lead_tys.size - lead_num - post_num).clamp(0, opt.size - 1)
          (opt.size - 1).times {|i| locals[lead_num + i] = i < opt_count ? lead_tys[lead_num + i] : Type.nil }

          # rest
          rest_b = lead_num + opt_count
          rest_e = [0, lead_tys.size - post_num].max
          locals[rest_index] = Type::Array.new(Type::Array::Elements.new(lead_tys[rest_b...rest_e] || [], Type.bot), Type::Instance.new(Type::Builtin[:ary]))

          # p0, p1
          off = [lead_num, lead_tys.size - post_num].max
          post_num.times {|i| locals[post_index + i] = lead_tys[off + i] || Type.nil }
        else
          # yield a0, a1, a2 -->
          #                do |l0, l1, o0=, o1=, p0, p1|
          # lead_ty argc == 0:  -   -   -    -    -   - (error if kind is method)
          # lead_ty argc == 1: a0   -   -    -    -   - (error if kind is method)
          # lead_ty argc == 2: a0  a1   -    -    -   - (error if kind is method)
          # lead_ty argc == 3: a0  a1   -    -   a2   - (error if kind is method)
          # lead_ty argc == 4: a0  a1   -    -   a2  a3
          # lead_ty argc == 5: a0  a1  a2    -   a3  a4
          # lead_ty argc == 6: a0  a1  a2   a3   a4  a5
          # lead_ty argc == 7: a0  a1  a2   a3   a4  a5 (if there is a6, report error if kind is method, or ignore if kind is block)
          #
          # l0 = a0
          # l1 = a1
          # o0 = a2
          # o1 = a3
          # p0 = a2|a3|a4
          # p1 = a3|a4|a5

          if kind == :method && (lead_tys.size < lead_num + post_num || lead_num + opt.size - 1 + post_num < lead_tys.size)
            return argument_error(lead_tys.size, lead_num + post_num, lead_num + post_num + opt.size - 1)
          end

          # l0, l1
          lead_num.times {|i| locals[i] = lead_tys[i] || Type.nil }

          # o0, o1
          opt_count = (lead_tys.size - lead_num - post_num).clamp(0, opt.size - 1)
          (opt.size - 1).times {|i| locals[lead_num + i] = i < opt_count ? lead_tys[lead_num + i] : Type.nil }

          # p0, p1
          off = lead_num + opt_count
          post_num.times {|i| locals[post_index + i] = lead_tys[off + i] || Type.nil }
        end
      end

      kw_tys = @kw_tys.dup
      if keyword
        keyword.each_with_index do |kw, i|
          case
          when kw.is_a?(Symbol) # required keyword
            key = kw
            req = true
          when kw.size == 2 # optional keyword (default value is a literal)
            key, default_ty = *kw
            default_ty = Type.guess_literal_type(default_ty)
            default_ty = default_ty.base_type if default_ty.is_a?(Type::Literal)
            req = false
          else # optional keyword (default value is an expression)
            key, = kw
            req = false
          end

          if kw_tys.key?(key)
            ty = kw_tys.delete(key)
          else
            ty = kw_tys[nil] || Type.bot
          end

          if ty == Type.bot && req
            return "no argument for required keywords"
          end

          ty = ty.union(default_ty) if default_ty
          locals[kw_index + i] = ty
        end
      end

      if kwrest_index
        if kw_tys.key?(nil)
          kw_rest_ty = Type.gen_hash {|h| h[Type.any] = kw_tys[nil] }
        else
          kw_rest_ty = Type.gen_hash do |h|
            kw_tys.each do |key, ty|
              sym = Type::Symbol.new(key, Type::Instance.new(Type::Builtin[:sym]))
              h[sym] = ty
            end
          end
        end
        locals[kwrest_index] = kw_rest_ty
      else
        if !kw_tys.empty?
          return "unknown keyword: #{ kw_tys.keys.join(", ") }"
        end
      end

      if block_index
        locals[block_index] = @blk_ty
      end

      start_pcs = opt[0..opt_count]

      return @blk_ty, start_pcs
    end
  end
end
