module TypeProf
  class MethodDef
    attr_accessor :pub_meth

    include Utils::StructuralEquality
  end

  class ISeqMethodDef < MethodDef
    def initialize(iseq, cref, outer_ep, pub_meth)
      @iseq = iseq
      raise if iseq.nil?
      @cref = cref
      @outer_ep = outer_ep
      @pub_meth = pub_meth
    end

    attr_reader :iseq

    def do_send(recv, mid, aargs, caller_ep, caller_env, scratch, &ctn)
      recv = recv.base_type while recv.respond_to?(:base_type)
      recv = scratch.globalize_type(recv, caller_env, caller_ep)
      aargs = scratch.globalize_type(aargs, caller_env, caller_ep)

      locals = [Type.nil] * @iseq.locals.size

      blk_ty, start_pcs = aargs.setup_formal_arguments(:method, locals, @iseq.fargs_format)
      if blk_ty.is_a?(String)
        scratch.error(caller_ep, blk_ty)
        ctn[Type.any, caller_ep, caller_env]
        return
      end

      nctx = Context.new(@iseq, @cref, mid)
      callee_ep = ExecutionPoint.new(nctx, 0, @outer_ep)
      nenv = Env.new(StaticEnv.new(recv, blk_ty, false, true), locals, [], Utils::HashWrapper.new({}))
      alloc_site = AllocationSite.new(callee_ep)
      locals.each_with_index do |ty, i|
        alloc_site2 = alloc_site.add_id(i)
        # nenv is top-level, so it is okay to call Type#localize directly
        nenv, ty = ty.localize(nenv, alloc_site2, Config.current.options[:type_depth_limit])
        nenv = nenv.local_update(i, ty)
      end

      start_pcs.each do |start_pc|
        scratch.merge_env(ExecutionPoint.new(nctx, start_pc, @outer_ep), nenv)
      end

      scratch.add_iseq_method_call!(self, nctx)
      scratch.add_callsite!(nctx, caller_ep, caller_env, &ctn)
    end

    def do_check_send(msig, recv, mid, ep, scratch)
      klass, singleton = recv.method_dispatch_info
      cur_subst = {}
      direct_method = true
      scratch.adjust_substitution(klass, singleton, mid, self, recv.generate_substitution) do |subst, direct|
        direct_method &&= direct
        cur_subst = Type.merge_substitution(cur_subst, subst)
      end

      lead_num = @iseq.fargs_format[:lead_num] || 0
      post_num = @iseq.fargs_format[:post_num] || 0
      rest_start = @iseq.fargs_format[:rest_start]
      opt = @iseq.fargs_format[:opt] || [0]

      # TODO: check keywords
      if rest_start
        # almost ok
      else
        if msig.rest_ty
          scratch.error(ep, "RBS says that a rest argument is accepted, but the method definition does not accept one")
          return
        end
        if msig.lead_tys.size + msig.post_tys.size < lead_num + post_num
          scratch.error(ep, "RBS says that the arity may be %d, but the method definition requires at least %d arguments" % [msig.lead_tys.size + msig.post_tys.size, lead_num + post_num])
          return
        end
        if msig.lead_tys.size + msig.opt_tys.size + msig.post_tys.size > lead_num + opt.size - 1 + post_num
          scratch.error(ep, "RBS says that the arity may be %d, but the method definition requires at most %d arguments" % [msig.lead_tys.size + msig.opt_tys.size + msig.post_tys.size, lead_num + opt.size - 1 + post_num])
          return
        end
      end

      lead_num = @iseq.fargs_format[:lead_num] || 0
      post_start = @iseq.fargs_format[:post_start]
      kw_start = @iseq.fargs_format[:kwbits]
      keyword = @iseq.fargs_format[:keyword]
      kw_start -= keyword.size if kw_start
      kw_rest = @iseq.fargs_format[:kwrest]
      block_start = @iseq.fargs_format[:block_start]

      # XXX: need to check .rbs msig and .rb fargs

      ctx = Context.new(@iseq, @cref, mid)
      callee_ep = ExecutionPoint.new(ctx, 0, @outer_ep)

      locals = [Type.nil] * @iseq.locals.size
      nenv = Env.new(StaticEnv.new(recv, msig.blk_ty, false, true), locals, [], Utils::HashWrapper.new({}))
      alloc_site = AllocationSite.new(callee_ep)
      idx = 0
      msig.lead_tys.each_with_index do |ty, i|
        alloc_site2 = alloc_site.add_id(idx += 1)
        ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
        nenv, ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
        nenv = nenv.local_update(i, ty)
      end
      if msig.opt_tys
        msig.opt_tys.each_with_index do |ty, i|
          alloc_site2 = alloc_site.add_id(idx += 1)
          ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
          nenv, ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
          nenv = nenv.local_update(lead_num + i, ty)
        end
      end
      if msig.rest_ty
        alloc_site2 = alloc_site.add_id(idx += 1)
        ty = Type::Array.new(Type::Array::Elements.new([], msig.rest_ty), Type::Instance.new(Type::Builtin[:ary]))
        ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
        nenv, rest_ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
        nenv = nenv.local_update(rest_start, rest_ty)
      end
      if msig.post_tys
        msig.post_tys.each_with_index do |ty, i|
          alloc_site2 = alloc_site.add_id(idx += 1)
          ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
          nenv, ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
          nenv = nenv.local_update(post_start + i, ty)
        end
      end
      if msig.kw_tys && keyword # TODO: support the case where RBS writes kw_tys and RB method accepts **kwrest
        msig.kw_tys.each do |_, key, ty|
          i = keyword.index {|callee_key,| callee_key == key }
          unless i
            # warn
            next
          end
          alloc_site2 = alloc_site.add_id(key)
          ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
          nenv, ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
          nenv = nenv.local_update(kw_start + i, ty)
        end
      end
      if msig.kw_rest_ty
        ty = msig.kw_rest_ty
        alloc_site2 = alloc_site.add_id(:**)
        ty = ty.substitute(cur_subst, Config.current.options[:type_depth_limit]).remove_type_vars
        nenv, ty = scratch.localize_type(ty, nenv, callee_ep, alloc_site2)
        nenv = nenv.local_update(kw_rest, ty)
      end
      nenv = nenv.local_update(block_start, msig.blk_ty) if block_start

      opt.each do |start_pc|
        scratch.merge_env(callee_ep.jump(start_pc), nenv)
      end
      scratch.add_executed_iseq(@iseq)

      ctx
    end
  end

  class AliasMethodDef < MethodDef
    def initialize(orig_mid, mdef, def_ep)
      @orig_mid = orig_mid
      @mdef = mdef
      @pub_meth = mdef.pub_meth
      @def_ep = def_ep
    end

    attr_reader :orig_mid, :mdef, :def_ep

    def do_send(recv, _mid, aargs, caller_ep, caller_env, scratch, &ctn)
      @mdef.do_send(recv, @orig_mid, aargs, caller_ep, caller_env, scratch, &ctn)
    end

    def do_check_send(msig, recv, mid, ep, scratch)
      @mdef.do_check_send(msig, recv, mid, ep, scratch)
    end
  end

  class AttrMethodDef < MethodDef
    def initialize(ivar, kind, pub_meth)
      @ivar = ivar
      @kind = kind # :reader | :writer
      @pub_meth = pub_meth
    end

    attr_reader :ivar, :kind

    def do_send(recv, mid, aargs, caller_ep, caller_env, scratch, &ctn)
      case @kind
      when :reader
        if aargs.lead_tys.size == 0
          scratch.add_ivar_read!(recv, @ivar, caller_ep) do |ty, _ep|
            ctn[ty, caller_ep, caller_env]
          end
        else
          ctn[Type.any, caller_ep, caller_env]
        end
      when :writer
        if aargs.lead_tys.size == 1
          ty = aargs.lead_tys[0]
          scratch.set_instance_variable(recv, @ivar, ty, caller_ep, caller_env)
          ctn[ty, caller_ep, caller_env]
        else
          ctn[Type.any, caller_ep, caller_env]
        end
      end
    end
  end

  class ExecutedAttrMethodDef < AttrMethodDef
    def initialize(ivar, kind, pub_meth, def_ep)
      super(ivar, kind, pub_meth)
      @def_ep = def_ep
    end

    attr_reader :def_ep
  end

  class TypedAttrMethodDef < AttrMethodDef
    def initialize(ivar, kind, pub_meth, rbs_source)
      @rbs_source = rbs_source

      super(ivar, kind, pub_meth)
    end

    attr_reader :rbs_source
  end

  class TypedMethodDef < MethodDef
    def initialize(sig_rets, rbs_source, pub_meth) # sig_rets: Array<[MethodSignature, (return)Type]>
      @sig_rets = sig_rets
      @rbs_source = rbs_source
      @pub_meth = pub_meth
      @iseq = nil
    end

    attr_reader :rbs_source, :iseq

    def do_send(recv_orig, mid, aargs, caller_ep, caller_env, scratch, &ctn)
      recv = scratch.globalize_type(recv_orig, caller_env, caller_ep)

      klass, singleton = recv_orig.method_dispatch_info
      cur_subst = {}
      direct_method = true
      scratch.adjust_substitution(klass, singleton, mid, self, recv.generate_substitution) do |subst, direct|
        direct_method &&= direct
        cur_subst = Type.merge_substitution(cur_subst, subst)
      end

      found = false
      aargs = scratch.globalize_type(aargs, caller_env, caller_ep)
      @sig_rets.each do |msig, ret_ty|
        ncaller_env = caller_env
        #pp [mid, aargs, msig]
        # XXX: support self type in msig
        subst = aargs.consistent_with_method_signature?(msig)
        next unless subst

        if direct_method && recv_orig.is_a?(Type::Local)
          ncaller_env = recv_orig.update_container_elem_type(subst, ncaller_env, caller_ep, scratch)
        end

        subst = Type.merge_substitution(subst, cur_subst)
        # need to check self tyvar?
        subst[Type::Var.new(:self)] = recv

        found = true
        if aargs.blk_ty.is_a?(Type::Proc)
          #raise NotImplementedError unless aargs.blk_ty.block_body.is_a?(ISeqBlock) # XXX
          dummy_ctx = TypedContext.new(caller_ep, mid)
          dummy_ep = ExecutionPoint.new(dummy_ctx, -1, caller_ep)
          s_recv = recv
          s_recv = s_recv.base_type while s_recv.respond_to?(:base_type)
          dummy_env = Env.new(StaticEnv.new(s_recv, msig.blk_ty, false, true), [], [], Utils::HashWrapper.new({}))
          if msig.blk_ty.is_a?(Type::Proc)
            scratch.add_callsite!(dummy_ctx, caller_ep, ncaller_env, &ctn)
            bsig = msig.blk_ty.block_body.msig
            alloc_site = AllocationSite.new(caller_ep).add_id(self)
            nlead_tys = (bsig.lead_tys + bsig.opt_tys).map.with_index do |ty, i|
              ty = ty.substitute(subst, Config.current.options[:type_depth_limit]).remove_type_vars
              dummy_env, ty = scratch.localize_type(ty, dummy_env, dummy_ep, alloc_site.add_id(i))
              ty
            end
            0.upto(bsig.opt_tys.size) do |n|
              naargs = ActualArguments.new(nlead_tys[0, bsig.lead_tys.size + n], nil, {}, Type.nil) # XXX: support block to block?
              scratch.do_invoke_block(aargs.blk_ty, naargs, dummy_ep, dummy_env) do |blk_ret_ty, _ep, _env|
                subst2 = Type.match?(blk_ret_ty, msig.blk_ty.block_body.ret_ty)
                if subst2
                  subst2 = Type.merge_substitution(subst, subst2)
                  if direct_method && recv_orig.is_a?(Type::Local)
                    ncaller_env = recv_orig.update_container_elem_type(subst2, ncaller_env, caller_ep, scratch)
                    scratch.merge_return_env(caller_ep) {|env| env ? env.merge(ncaller_env) : ncaller_env }
                  end
                  ret_ty2 = ret_ty.substitute(subst2, Config.current.options[:type_depth_limit]).remove_type_vars
                else
                  ret_ty2 = Type.any
                end
                # XXX: check the return type from the block
                # sig.blk_ty.block_body.ret_ty.eql?(_ret_ty) ???
                scratch.add_return_value!(dummy_ctx, ret_ty2)
              end
              # scratch.add_return_value!(dummy_ctx, ret_ty) ?
              # This makes `def foo; 1.times { return "str" }; end` return Integer|String
            end
          else
            # XXX: a block is passed to a method that does not accept block.
            # Should we call the passed block with any arguments?
            ret_ty = ret_ty.remove_type_vars
            ctn[ret_ty, caller_ep, ncaller_env] if ret_ty != Type.bot
          end
        else
          ret_ty = ret_ty.substitute(subst, Config.current.options[:type_depth_limit])
          ret_ty = ret_ty.remove_type_vars
          ctn[ret_ty, caller_ep, ncaller_env] if ret_ty != Type.bot
        end
      end

      unless found
        scratch.error(caller_ep, "failed to resolve overload: #{ recv.screen_name(scratch) }##{ mid }")
        ctn[Type.any, caller_ep, caller_env]
      end
    end

    def do_match_iseq_mdef(iseq_mdef, recv, mid, env, ep, scratch)
      recv = scratch.globalize_type(recv, env, ep)
      @sig_rets.each do |msig, _ret_ty|
        iseq_mdef.do_check_send(msig, recv, mid, ep, scratch)
      end
      @iseq ||= iseq_mdef.iseq
    end
  end

  class CustomMethodDef < MethodDef
    def initialize(impl, pub_meth)
      @impl = impl
      @pub_meth = pub_meth
    end

    def do_send(recv, mid, aargs, caller_ep, caller_env, scratch, &ctn)
      @impl[recv, mid, aargs, caller_ep, caller_env, scratch, &ctn]
    end
  end
end
