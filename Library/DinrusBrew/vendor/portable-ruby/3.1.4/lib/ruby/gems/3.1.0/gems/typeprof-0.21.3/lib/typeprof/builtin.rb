module TypeProf
  module Builtin
    module_function

    def get_sym(target, ty, ep, scratch)
      unless ty.is_a?(Type::Symbol)
        scratch.warn(ep, "symbol expected")
        return
      end
      sym = ty.sym
      unless sym
        scratch.warn(ep, "dynamic symbol is given to #{ target }; ignored")
        return
      end
      sym
    end

    def vmcore_set_method_alias(recv, mid, aargs, ep, env, scratch, &ctn)
      klass, new_mid, old_mid = aargs.lead_tys
      new_sym = get_sym("alias", new_mid, ep, scratch) or return
      old_sym = get_sym("alias", old_mid, ep, scratch) or return
      scratch.alias_method(klass, ep.ctx.cref.singleton, new_sym, old_sym, ep)
      ctn[Type.nil, ep, env]
    end

    def vmcore_undef_method(recv, mid, aargs, ep, env, scratch, &ctn)
      # no-op
      ctn[Type.nil, ep, env]
    end

    def vmcore_hash_merge_kwd(recv, mid, aargs, ep, env, scratch, &ctn)
      h1 = aargs.lead_tys[0]
      h2 = aargs.lead_tys[1]
      elems = nil
      h1.each_child do |h1|
        if h1.is_a?(Type::Local) && h1.kind == Type::Hash
          h1_elems = scratch.get_container_elem_types(env, ep, h1.id)
          h2.each_child do |h2|
            if h2.is_a?(Type::Local) && h2.kind == Type::Hash
              h2_elems = scratch.get_container_elem_types(env, ep, h2.id)
              elems0 = h1_elems.union(h2_elems)
              if elems
                elems = elems.union(elems0)
              else
                elems = elems0
              end
            end
          end
        end
      end
      elems ||= Type::Hash::Elements.new({Type.any => Type.any})
      base_ty = Type::Instance.new(Type::Builtin[:hash])
      ret_ty = Type::Hash.new(elems, base_ty)
      ctn[ret_ty, ep, env]
    end

    def vmcore_raise(recv, mid, aargs, ep, env, scratch, &ctn)
      # no-op
    end

    def lambda(recv, mid, aargs, ep, env, scratch, &ctn)
      ctn[aargs.blk_ty, ep, env]
    end

    def proc_call(recv, mid, aargs, ep, env, scratch, &ctn)
      scratch.do_invoke_block(recv, aargs, ep, env, &ctn)
    end

    def object_s_new(recv, mid, aargs, ep, env, scratch, &ctn)
      if recv.type_params.size >= 1
        ty = Type::ContainerType.create_empty_instance(recv)
        env, ty = scratch.localize_type(ty, env, ep, AllocationSite.new(ep).add_id(:object_s_new))
      else
        ty = Type::Instance.new(recv)
      end
      meths = scratch.get_method(recv, false, false, :initialize)
      meths.flat_map do |meth|
        meth.do_send(ty, :initialize, aargs, ep, env, scratch) do |_ret_ty, ep, env|
          ctn[ty, ep, env]
        end
      end
    end

    def object_is_a?(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size == 1
        if recv.is_a?(Type::Instance)
          if recv.klass == aargs.lead_tys[0] # XXX: inheritance
            true_val = Type::Instance.new(Type::Builtin[:true])
            ctn[true_val, ep, env]
          else
            false_val = Type::Instance.new(Type::Builtin[:false])
            ctn[false_val, ep, env]
          end
        else
          ctn[Type.bool, ep, env]
        end
      else
        ctn[Type.bool, ep, env]
      end
    end

    def object_respond_to?(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size == 1
        sym = get_sym("respond_to?", aargs.lead_tys[0], ep, scratch)
        if sym
          klass, singleton = recv.method_dispatch_info
          if scratch.get_method(klass, singleton, false, sym)
            true_val = Type::Instance.new(Type::Builtin[:true])
            ctn[true_val, ep, env]
          else
            false_val = Type::Instance.new(Type::Builtin[:false])
            ctn[false_val, ep, env]
          end
        else
          ctn[Type.bool, ep, env]
        end
      else
        ctn[Type.bool, ep, env]
      end
    end

    def object_class(recv, mid, aargs, ep, env, scratch, &ctn)
      if recv.is_a?(Type::Instance)
        ctn[recv.klass, ep, env]
      else
        ctn[Type.any, ep, env]
      end
    end

    def object_send(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size >= 1
        mid_ty, = aargs.lead_tys
      elsif aargs.rest_ty
        mid_ty = aargs.rest_ty
      else
        return ctn[Type.any, ep, env]
      end
      aargs = ActualArguments.new(aargs.lead_tys[1..] || [], aargs.rest_ty, aargs.kw_tys, aargs.blk_ty)
      found = false
      mid_ty.each_child do |mid|
        if mid.is_a?(Type::Symbol)
          found = true
          mid = mid.sym
          scratch.do_send(recv, mid, aargs, ep, env, &ctn)
        end
      end
      unless found
        ctn[Type.any, ep, env]
      end
    end

    def object_instance_eval(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size >= 1
        scratch.warn(ep, "instance_eval with arguments is ignored")
        ctn[Type.any, ep, env]
        return
      end
      naargs = ActualArguments.new([recv], nil, {}, Type.nil)
      nrecv = recv
      nrecv = nrecv.base_type if nrecv.is_a?(Type::ContainerType)
      scratch.do_invoke_block(aargs.blk_ty, naargs, ep, env, replace_recv_ty: nrecv) do |ret_ty, ep|
        ctn[ret_ty, ep, env]
      end
    end

    def module_eqq(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size == 1
        aargs.lead_tys[0].each_child do |aarg|
          aarg = aarg.base_type if aarg.is_a?(Type::Symbol) # XXX
          if aarg.is_a?(Type::Instance)
            if aarg.klass == recv # XXX: inheritance
              true_val = Type::Instance.new(Type::Builtin[:true])
              ctn[true_val, ep, env]
            else
              false_val = Type::Instance.new(Type::Builtin[:false])
              ctn[false_val, ep, env]
            end
          else
            ctn[Type.bool, ep, env]
          end
        end
      else
        ctn[Type.bool, ep, env]
      end
    end

    def object_module_eval(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size >= 1
        scratch.warn(ep, "class_eval with arguments is ignored")
        ctn[Type.any, ep, env]
        return
      end
      naargs = ActualArguments.new([recv], nil, {}, Type.nil)
      nrecv = recv
      nrecv = nrecv.base_type if nrecv.is_a?(Type::ContainerType)
      ncref = ep.ctx.cref.extend(nrecv, true)
      scratch.do_invoke_block(aargs.blk_ty, naargs, ep, env, replace_recv_ty: nrecv, replace_cref: ncref) do |_ret_ty, ep|
        ctn[recv, ep, env]
      end
    end

    def object_enum_for(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size >= 1
        mid_ty, = aargs.lead_tys
        naargs = ActualArguments.new(aargs.lead_tys[1..], aargs.rest_ty, aargs.kw_tys, aargs.blk_ty)
      elsif aargs.rest_ty
        mid_ty = aargs.rest_ty
        naargs = aargs
      else
        mid_ty = Type::Symbol.new(:each, Type::Instance.new(Type::Builtin[:sym]))
        naargs = aargs
      end

      elem_ty = Type.bot
      enum_for_blk = CustomBlock.new(ep, mid) do |aargs, caller_ep, caller_env, scratch, replace_recv_ty:, replace_cref:, &blk_ctn|
        if aargs.lead_tys.size >= 1
          elem_ty = elem_ty.union(aargs.lead_tys[0])
        else
          elem_ty = elem_ty.union(Type.any)
        end
        ctn[Type::Cell.new(Type::Cell::Elements.new([elem_ty, Type.any]), Type::Instance.new(Type::Builtin[:enumerator])), ep, env]
        blk_ctn[Type.any, caller_ep, caller_env]
      end
      enum_for_blk_ty = Type::Proc.new(enum_for_blk, Type::Instance.new(Type::Builtin[:proc]))

      naargs = ActualArguments.new(naargs.lead_tys, naargs.rest_ty, naargs.kw_tys, enum_for_blk_ty)
      mid_ty.each_child do |mid|
        if mid.is_a?(Type::Symbol)
          mid = mid.sym
          scratch.do_send(recv, mid, naargs, ep, env) do |_ret_ty, _ep|
            ctn[Type::Cell.new(Type::Cell::Elements.new([elem_ty, Type.any]), Type::Instance.new(Type::Builtin[:enumerator])), ep, env]
          end
        end
      end
    end

    def object_privitive_method(recv, mid, aargs, ep, env, scratch, &ctn)
      ctn[Type::Symbol.new(ep.ctx.mid, Type::Instance.new(Type::Builtin[:sym])), ep, env]
    end

    def object_block_given?(recv, mid, aargs, ep, env, scratch, &ctn)
      procs = Type.bot
      no_proc = false
      env.static_env.blk_ty.each_child do |blk_ty|
        case blk_ty
        when Type::Proc
          procs = procs.union(blk_ty)
        when Type.nil
          no_proc = true
        else
          ctn[Type.bool, ep, env]
        end
      end
      if procs != Type.bot
        ctn[Type::Instance.new(Type::Builtin[:true]), ep, env.replace_blk_ty(procs)]
      end
      if no_proc
        ctn[Type::Instance.new(Type::Builtin[:false]), ep, env.replace_blk_ty(Type.nil)]
      end
    end

    def module_include(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        scratch.warn(ep, "Module#include without an argument is ignored")
        ctn[Type.any, ep, env]
        return
      end

      unless recv.is_a?(Type::Class)
        # XXX: warn?
        return ctn[Type.any, ep, env]
      end

      # support multiple arguments: include M1, M2
      arg = aargs.lead_tys[0]
      arg.each_child do |arg|
        if arg.is_a?(Type::Class)
          aargs = ActualArguments.new([recv], nil, {}, Type.nil)
          scratch.do_send(arg, :included, aargs, ep, env) {|_ret_ty, _ep| }
          scratch.mix_module(:after, recv, arg, nil, ep.ctx.cref.singleton, ep)
        end
      end
      ctn[recv, ep, env]
    end

    def module_extend(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        scratch.warn(ep, "Module#extend without an argument is ignored")
        ctn[Type.any, ep, env]
        return
      end

      unless recv.is_a?(Type::Class)
        # XXX: warn?
        return ctn[Type.any, ep, env]
      end

      arg = aargs.lead_tys[0]
      arg.each_child do |arg|
        if arg.is_a?(Type::Class)
          aargs = ActualArguments.new([recv], nil, {}, Type.nil)
          scratch.do_send(arg, :extended, aargs, ep, env) {|_ret_ty, _ep| }
          # if ep.ctx.cref.singleton is true, the meta-meta level is ignored. Should we warn?
          scratch.mix_module(:after, recv, arg, nil, true, ep)
        end
      end
      ctn[recv, ep, env]
    end

    def module_prepend(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        scratch.warn(ep, "Module#prepend without an argument is ignored")
        ctn[Type.any, ep, env]
        return
      end

      unless recv.is_a?(Type::Class)
        # XXX: warn?
        return ctn[Type.any, ep, env]
      end

      arg = aargs.lead_tys[0]
      arg.each_child do |arg|
        if arg.is_a?(Type::Class)
          scratch.mix_module(:before, recv, arg, nil, ep.ctx.cref.singleton, ep)
        end
      end
      ctn[recv, ep, env]
    end

    def module_module_function(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.empty?
        ctn[recv, ep, env.enable_module_function]
      else
        aargs.lead_tys.each do |aarg|
          sym = get_sym("module_function", aarg, ep, scratch) or next
          meths = scratch.get_method(recv, false, false, sym)
          meths.each do |mdef|
            scratch.add_method(recv, sym, true, mdef)
          end
        end
        ctn[recv, ep, env]
      end
    end

    def module_public(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.empty?
        ctn[recv, ep, env.method_public_set(true)]
      else
        if recv.is_a?(Type::Class)
          aargs.lead_tys.each do |aarg|
            sym = get_sym("public", aarg, ep, scratch) or next
            meths = scratch.get_method(recv, false, false, sym)
            next unless meths
            meths.each do |mdef|
              mdef.pub_meth = true if mdef.respond_to?(:pub_meth=)
            end
          end
        else
          # XXX: warn?
        end
        ctn[recv, ep, env]
      end
    end

    def module_private(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.empty?
        ctn[recv, ep, env.method_public_set(false)]
      else
        if recv.is_a?(Type::Class)
          aargs.lead_tys.each do |aarg|
            sym = get_sym("private", aarg, ep, scratch) or next
            meths = scratch.get_method(recv, false, false, sym)
            next unless meths
            meths.each do |mdef|
              mdef.pub_meth = false if mdef.respond_to?(:pub_meth=)
            end
          end
        else
          # XXX: warn?
        end
        ctn[recv, ep, env]
      end
    end

    def module_define_method(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        scratch.warn(ep, "Module#define with #{ aargs.lead_tys.size } argument is ignored")
        ctn[Type.any, ep, env]
        return
      end

      mid, = aargs.lead_tys
      mid.each_child do |mid|
        if mid.is_a?(Type::Symbol)
          mid = mid.sym
          aargs.blk_ty.each_child do |blk_ty|
            if blk_ty.is_a?(Type::Proc)
              blk = blk_ty.block_body
              case blk
              when ISeqBlock
                scratch.do_define_iseq_method(ep, env, mid, blk.iseq, blk.outer_ep)
              else
                # XXX: what to do?
              end
            else
              # XXX: what to do?
            end
          end
        else
          # XXX: what to do?
        end
      end
      ctn[Type.any, ep, env]
    end

    def module_attr_accessor(recv, mid, aargs, ep, env, scratch, &ctn)
      aargs.lead_tys.each do |aarg|
        sym = get_sym("attr_accessor", aarg, ep, scratch) or next
        cref = ep.ctx.cref
        scratch.add_attr_method(cref.klass, sym, :"@#{ sym }", :accessor, env.static_env.pub_meth, ep)
      end
      ctn[Type.nil, ep, env]
    end

    def module_attr_reader(recv, mid, aargs, ep, env, scratch, &ctn)
      aargs.lead_tys.each do |aarg|
        sym = get_sym("attr_reader", aarg, ep, scratch) or next
        cref = ep.ctx.cref
        scratch.add_attr_method(cref.klass, sym, :"@#{ sym }", :reader, env.static_env.pub_meth, ep)
      end
      ctn[Type.nil, ep, env]
    end

    def module_attr_writer(recv, mid, aargs, ep, env, scratch, &ctn)
      aargs.lead_tys.each do |aarg|
        sym = get_sym("attr_writer", aarg, ep, scratch) or next
        cref = ep.ctx.cref
        scratch.add_attr_method(cref.klass, sym, :"@#{ sym }", :writer, env.static_env.pub_meth, ep)
      end
      ctn[Type.nil, ep, env]
    end

    def kernel_p(recv, mid, aargs, ep, env, scratch, &ctn)
      aargs.lead_tys.each do |aarg|
        scratch.reveal_type(ep, scratch.globalize_type(aarg, env, ep))
      end
      ctn[aargs.lead_tys.size == 1 ? aargs.lead_tys.first : Type.any, ep, env]
    end

    def array_aref(recv, mid, aargs, ep, env, scratch, &ctn)
      return ctn[Type.any, ep, env] unless recv.is_a?(Type::Local) && recv.kind == Type::Array

      case aargs.lead_tys.size
      when 1
        idx = aargs.lead_tys.first
        if idx.is_a?(Type::Literal)
          idx = idx.lit
          idx = nil if !idx.is_a?(Integer) && !idx.is_a?(Range)
        elsif idx == Type::Instance.new(Type::Builtin[:range])
          idx = (nil..nil)
        else
          idx = nil
        end
        ty = scratch.get_array_elem_type(env, ep, recv.id, idx)
        ctn[ty, ep, env]
      when 2
        ty = scratch.get_array_elem_type(env, ep, recv.id)
        base_ty = Type::Instance.new(Type::Builtin[:ary])
        ret_ty = Type::Array.new(Type::Array::Elements.new([], ty), base_ty)
        ctn[ret_ty, ep, env]
      else
        ctn[Type.any, ep, env]
      end
    end

    def array_aset(recv, mid, aargs, ep, env, scratch, &ctn)
      return ctn[Type.any, ep, env] unless recv.is_a?(Type::Local) && recv.kind == Type::Array

      if aargs.lead_tys.size != 2
        # XXX: Support `ary[idx, len] = val`
        #raise NotImplementedError # XXX
        return ctn[Type.any, ep, env]
      end

      idx = aargs.lead_tys.first
      if idx.is_a?(Type::Literal)
        idx = idx.lit
        if !idx.is_a?(Integer)
          # XXX: Support `ary[idx..end] = val`
          #raise NotImplementedError # XXX
          return ctn[Type.any, ep, env]
        end
      else
        idx = nil
      end

      ty = aargs.lead_tys.last

      env = scratch.update_container_elem_types(env, ep, recv.id, recv.base_type) do |elems|
        elems.update(idx, ty)
      end

      ctn[ty, ep, env]
    end

    def array_pop(recv, mid, aargs, ep, env, scratch, &ctn)
      return ctn[Type.any, ep, env] unless recv.is_a?(Type::Local) && recv.kind == Type::Array

      if aargs.lead_tys.size != 0
        ctn[Type.any, ep, env]
        return
      end

      ty = scratch.get_array_elem_type(env, ep, recv.id)
      ctn[ty, ep, env]
    end

    def hash_aref(recv, mid, aargs, ep, env, scratch, &ctn)
      return ctn[Type.any, ep, env] unless recv.is_a?(Type::Local) && recv.kind == Type::Hash

      if aargs.lead_tys.size != 1
        ctn[Type.any, ep, env]
        return
      end
      idx = aargs.lead_tys.first
      recv.each_child do |recv|
        if recv.is_a?(Type::Local) && recv.kind == Type::Hash
          ty = scratch.get_hash_elem_type(env, ep, recv.id, idx)
          ty = Type.nil if ty == Type.bot
        else
          ty = Type.any
        end
        ctn[ty, ep, env]
      end
    end

    def hash_aset(recv, mid, aargs, ep, env, scratch, &ctn)
      return ctn[Type.any, ep, env] unless recv.is_a?(Type::Local) && recv.kind == Type::Hash

      if aargs.lead_tys.size != 2
        # XXX: error?
        ctn[Type.any, ep, env]
        return
      end

      idx = aargs.lead_tys.first
      idx = scratch.globalize_type(idx, env, ep)
      ty = aargs.lead_tys.last

      unless recv.is_a?(Type::Local) && recv.kind == Type::Hash
        # to ignore: class OptionMap < Hash
        return ctn[ty, ep, env]
      end

      env = scratch.update_container_elem_types(env, ep, recv.id, recv.base_type) do |elems|
        elems.update(idx, ty)
      end

      ctn[ty, ep, env]
    end

    def struct_initialize(recv, mid, aargs, ep, env, scratch, &ctn)
      struct_klass = recv.klass
      while struct_klass.superclass != Type::Builtin[:struct]
        struct_klass = struct_klass.superclass
      end
      if struct_klass.superclass != Type::Builtin[:struct]
        ctn[Type.any, ep, env]
        return
      end
      scratch.add_ivar_read!(Type::Instance.new(struct_klass), :_keyword_init, ep) do |keyword_init, ep|
        scratch.add_ivar_read!(Type::Instance.new(struct_klass), :_members, ep) do |member_ary_ty, ep|
          next if member_ary_ty == Type.nil
          if keyword_init == Type::Instance.new(Type::Builtin[:true])
            # TODO: support kw_rest_ty
            aargs.kw_tys.each do |key, val_ty|
              found = false
              member_ary_ty.elems.lead_tys.each do |sym|
                if sym.sym == key
                  found = true
                  scratch.set_instance_variable(recv, sym.sym, val_ty, ep, env)
                end
              end
              unless found
                # TODO: what to do when not found?
              end
            end
          else
            member_ary_ty.elems.lead_tys.zip(aargs.lead_tys) do |sym, ty|
              ty ||= Type.nil
              scratch.set_instance_variable(recv, sym.sym, ty, ep, env)
            end
          end
        end
      end
      ctn[recv, ep, env]
    end

    def struct_s_new(recv, mid, aargs, ep, env, scratch, &ctn)
      keyword_init = false
      if aargs.kw_tys && aargs.kw_tys[:keyword_init] # XXX: more canonical way to extract keyword...
        if aargs.kw_tys[:keyword_init] == Type::Instance.new(Type::Builtin[:true])
          keyword_init = true
        end
      end

      fields = aargs.lead_tys.map {|ty| get_sym("Struct.new", ty, ep, scratch) }.compact
      struct_klass = scratch.new_struct(ep)

      scratch.set_singleton_custom_method(struct_klass, :new, Builtin.method(:object_s_new))
      scratch.set_singleton_custom_method(struct_klass, :[], Builtin.method(:object_s_new))
      fields.each do |field|
        scratch.add_attr_method(struct_klass, field, field, :accessor, true, ep)
      end
      fields = fields.map {|field| Type::Symbol.new(field, Type::Instance.new(Type::Builtin[:sym])) }
      base_ty = Type::Instance.new(Type::Builtin[:ary])
      fields = Type::Array.new(Type::Array::Elements.new(fields), base_ty)
      scratch.add_ivar_write!(Type::Instance.new(struct_klass), :_members, fields, ep)
      scratch.add_ivar_write!(Type::Instance.new(struct_klass), :_keyword_init, Type::Instance.new(Type::Builtin[:true]), ep) if keyword_init
      #set_singleton_custom_method(struct_klass, :members, Builtin.method(:...))

      ctn[struct_klass, ep, env]
    end

    def self.file_load(path, ep, env, scratch, &ctn)
      iseq, = ISeq.compile(path)
      callee_ep, callee_env = TypeProf.starting_state(iseq)
      scratch.merge_env(callee_ep, callee_env)

      scratch.add_callsite!(callee_ep.ctx, ep, env) do |_ret_ty, ep|
        ret_ty = Type::Instance.new(Type::Builtin[:true])
        ctn[ret_ty, ep, env]
      end
    end

    def self.file_require(feature, scratch)
      # XXX: dynamic RBS load is really needed??  Another idea:
      #
      # * RBS should be loaded in advance of analysis
      # * require "some_gem/foo" should be ignored
      # * require "app/foo" should always load .rb file (in this case, app/foo.rb)
      return :done, :true if Import.import_library(scratch, feature)

      # Try to analyze the source code of the gem
      begin
        gem feature
      rescue Gem::MissingSpecError, Gem::LoadError
      end

      begin
        filetype, path = $LOAD_PATH.resolve_feature_path(feature)

        if filetype == :rb
          return :done, :false if scratch.loaded_files[path]
          scratch.loaded_files[path] = true

          return :do, path if File.readable?(path)

          return :error, "failed to load: #{ path }"
        else
          return :error, "cannot load a .so file: #{ path }"
        end
      rescue LoadError
        return :error, "failed to require: #{ feature }"
      end
    end

    def kernel_require(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        # XXX: handle correctly
        ctn[Type.any, ep, env]
        return
      end

      feature = aargs.lead_tys.first
      if feature.is_a?(Type::Literal)
        feature = feature.lit

        unless feature.is_a?(String)
          return ctn[Type.any, ep, env]
        end

        action, arg = Builtin.file_require(feature, scratch)
        case action
        when :do
          Builtin.file_load(arg, ep, env, scratch, &ctn)
        when :done
          result = Type::Instance.new(Type::Builtin[arg])
          ctn[result, ep, env]
        when :error
          scratch.warn(ep, arg)
          result = Type.bool
          ctn[result, ep, env]
        end
      else
        scratch.warn(ep, "require target cannot be identified statically")
        result = Type.bool
        ctn[result, ep, env]
      end
    end

    def kernel_require_relative(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 1
        # XXX: handle correctly
        ctn[Type.any, ep, env]
        return
      end

      feature = aargs.lead_tys.first
      if feature.is_a?(Type::Literal)
        feature = feature.lit

        unless feature.is_a?(String)
          return ctn[Type.any, ep, env]
        end

        path = File.join(File.dirname(ep.ctx.iseq.absolute_path), feature) + ".rb" # XXX

        if scratch.loaded_files[path]
          result = Type::Instance.new(Type::Builtin[:false])
          return ctn[result, ep, env]
        end
        scratch.loaded_files[path] = true

        return Builtin.file_load(path, ep, env, scratch, &ctn) if File.readable?(path)

        scratch.warn(ep, "failed to load: #{ path }")
      else
        scratch.warn(ep, "require target cannot be identified statically")
        feature = nil
      end

      result = Type::Instance.new(Type::Builtin[:true])
      ctn[result, ep, env]
    end

    def kernel_autoload(recv, mid, aargs, ep, env, scratch, &ctn)
      if aargs.lead_tys.size != 2
        # XXX: handle correctly
        ctn[Type.any, ep, env]
        return
      end

      feature = aargs.lead_tys[1]
      if feature.is_a?(Type::Literal)
        feature = feature.lit

        action, arg = Builtin.file_require(feature, scratch)
        case action
        when :do
          Builtin.file_load(arg, ep, env, scratch, &ctn)
        when :done
        when :error
          scratch.warn(ep, arg)
        end
        ctn[Type.nil, ep, env]
      else
        scratch.warn(ep, "autoload target cannot be identified statically")
        ctn[Type.nil, ep, env]
      end
    end

    def module_autoload(recv, mid, aargs, ep, env, scratch, &ctn)
      kernel_autoload(recv, mid, aargs, ep, env, scratch, &ctn)
    end

    def kernel_Array(recv, mid, aargs, ep, env, scratch, &ctn)
      raise NotImplementedError if aargs.lead_tys.size != 1
      ty = aargs.lead_tys.first
      ty = scratch.globalize_type(ty, env, ep)
      all_ty = Type.bot
      ty.each_child_global do |ty|
        if ty.is_a?(Type::Array)
          all_ty = all_ty.union(ty)
        else
          base_ty = Type::Instance.new(Type::Builtin[:ary])
          ret_ty = Type::Array.new(Type::Array::Elements.new([ty]), base_ty)
          all_ty = all_ty.union(ret_ty)
        end
      end
      ctn[all_ty, ep, env]
    end

    def self.setup_initial_global_env(scratch)
      klass_basic_obj = scratch.new_class(nil, :BasicObject, [], :__root__, nil) # cbase, name, superclass
      klass_obj = scratch.new_class(nil, :Object, [], klass_basic_obj, nil)
      scratch.add_constant(klass_obj, :Object, klass_obj, nil)
      scratch.add_constant(klass_obj, :BasicObject, klass_basic_obj, nil)

      Type::Builtin[:basic_obj] = klass_basic_obj
      Type::Builtin[:obj]   = klass_obj

      Import.import_builtin(scratch)

      Type::Builtin[:vmcore]     , = scratch.new_class(klass_obj, :VMCore, [], klass_obj, nil)
      Type::Builtin[:int]        , = scratch.get_constant(klass_obj, :Integer)
      Type::Builtin[:float]      , = scratch.get_constant(klass_obj, :Float)
      Type::Builtin[:rational]   , = scratch.get_constant(klass_obj, :Rational)
      Type::Builtin[:complex]    , = scratch.get_constant(klass_obj, :Complex)
      Type::Builtin[:sym]        , = scratch.get_constant(klass_obj, :Symbol)
      Type::Builtin[:str]        , = scratch.get_constant(klass_obj, :String)
      Type::Builtin[:struct]     , = scratch.get_constant(klass_obj, :Struct)
      Type::Builtin[:ary]        , = scratch.get_constant(klass_obj, :Array)
      Type::Builtin[:hash]       , = scratch.get_constant(klass_obj, :Hash)
      Type::Builtin[:io]         , = scratch.get_constant(klass_obj, :IO)
      Type::Builtin[:proc]       , = scratch.get_constant(klass_obj, :Proc)
      Type::Builtin[:range]      , = scratch.get_constant(klass_obj, :Range)
      Type::Builtin[:regexp]     , = scratch.get_constant(klass_obj, :Regexp)
      Type::Builtin[:matchdata]  , = scratch.get_constant(klass_obj, :MatchData)
      Type::Builtin[:class]      , = scratch.get_constant(klass_obj, :Class)
      Type::Builtin[:module]     , = scratch.get_constant(klass_obj, :Module)
      Type::Builtin[:exc]        , = scratch.get_constant(klass_obj, :Exception)
      Type::Builtin[:encoding]   , = scratch.get_constant(klass_obj, :Encoding)
      Type::Builtin[:enumerator] , = scratch.get_constant(klass_obj, :Enumerator)
      Type::Builtin[:kernel]     , = scratch.get_constant(klass_obj, :Kernel)

      klass_vmcore = Type::Builtin[:vmcore]
      klass_ary    = Type::Builtin[:ary]
      klass_hash   = Type::Builtin[:hash]
      klass_struct = Type::Builtin[:struct]
      klass_proc   = Type::Builtin[:proc]
      klass_module = Type::Builtin[:module]

      scratch.set_custom_method(klass_vmcore, :"core#set_method_alias", Builtin.method(:vmcore_set_method_alias))
      scratch.set_custom_method(klass_vmcore, :"core#undef_method", Builtin.method(:vmcore_undef_method))
      scratch.set_custom_method(klass_vmcore, :"core#hash_merge_kwd", Builtin.method(:vmcore_hash_merge_kwd))
      scratch.set_custom_method(klass_vmcore, :"core#raise", Builtin.method(:vmcore_raise))

      scratch.set_custom_method(klass_vmcore, :lambda, Builtin.method(:lambda))
      scratch.set_singleton_custom_method(klass_obj, :"new", Builtin.method(:object_s_new))
      scratch.set_custom_method(klass_obj, :p, Builtin.method(:kernel_p), false)
      scratch.set_custom_method(klass_obj, :is_a?, Builtin.method(:object_is_a?))
      scratch.set_custom_method(klass_obj, :respond_to?, Builtin.method(:object_respond_to?))
      scratch.set_custom_method(klass_obj, :class, Builtin.method(:object_class))
      scratch.set_custom_method(klass_obj, :send, Builtin.method(:object_send))
      scratch.set_custom_method(klass_obj, :instance_eval, Builtin.method(:object_instance_eval))
      scratch.set_custom_method(klass_obj, :proc, Builtin.method(:lambda), false)
      scratch.set_custom_method(klass_obj, :__method__, Builtin.method(:object_privitive_method), false)
      scratch.set_custom_method(klass_obj, :block_given?, Builtin.method(:object_block_given?), false)

      scratch.set_custom_method(klass_obj, :enum_for, Builtin.method(:object_enum_for))
      scratch.set_custom_method(klass_obj, :to_enum, Builtin.method(:object_enum_for))

      scratch.set_custom_method(klass_module, :include, Builtin.method(:module_include))
      scratch.set_custom_method(klass_module, :extend, Builtin.method(:module_extend))
      scratch.set_custom_method(klass_module, :prepend, Builtin.method(:module_prepend))
      scratch.set_custom_method(klass_module, :module_function, Builtin.method(:module_module_function), false)
      scratch.set_custom_method(klass_module, :public, Builtin.method(:module_public), false)
      scratch.set_custom_method(klass_module, :private, Builtin.method(:module_private), false)
      scratch.set_custom_method(klass_module, :define_method, Builtin.method(:module_define_method))
      scratch.set_custom_method(klass_module, :attr_accessor, Builtin.method(:module_attr_accessor))
      scratch.set_custom_method(klass_module, :attr_reader, Builtin.method(:module_attr_reader))
      scratch.set_custom_method(klass_module, :attr_writer, Builtin.method(:module_attr_writer))
      scratch.set_custom_method(klass_module, :class_eval, Builtin.method(:object_module_eval))
      scratch.set_custom_method(klass_module, :module_eval, Builtin.method(:object_module_eval))
      scratch.set_custom_method(klass_module, :===, Builtin.method(:module_eqq))

      scratch.set_custom_method(klass_proc, :[], Builtin.method(:proc_call))
      scratch.set_custom_method(klass_proc, :call, Builtin.method(:proc_call))

      scratch.set_custom_method(klass_ary, :[], Builtin.method(:array_aref))
      scratch.set_custom_method(klass_ary, :[]=, Builtin.method(:array_aset))
      scratch.set_custom_method(klass_ary, :pop, Builtin.method(:array_pop))

      scratch.set_custom_method(klass_hash, :[], Builtin.method(:hash_aref))
      scratch.set_custom_method(klass_hash, :[]=, Builtin.method(:hash_aset))

      scratch.set_custom_method(klass_struct, :initialize, Builtin.method(:struct_initialize))
      scratch.set_singleton_custom_method(klass_struct, :new, Builtin.method(:struct_s_new))

      scratch.set_custom_method(klass_obj, :require, Builtin.method(:kernel_require), false)
      scratch.set_custom_method(klass_obj, :require_relative, Builtin.method(:kernel_require_relative), false)
      scratch.set_custom_method(klass_obj, :Array, Builtin.method(:kernel_Array), false)
      scratch.set_custom_method(klass_obj, :autoload, Builtin.method(:kernel_autoload), false)
      scratch.set_custom_method(klass_module, :autoload, Builtin.method(:module_autoload))

      # remove BasicObject#method_missing
      scratch.set_method(klass_basic_obj, :method_missing, false, nil)

      # ENV: Hash[String, String]
      str_ty = Type::Instance.new(Type::Builtin[:str])
      env_ty = Type.gen_hash {|h| h[str_ty] = Type.optional(str_ty) }
      scratch.add_constant(klass_obj, :ENV, env_ty, nil)

      scratch.search_method(Type::Builtin[:kernel], false, :sprintf) do |mdefs,|
        mdefs.each do |mdef|
          scratch.add_method(klass_vmcore, :"core#sprintf", false, mdef)
        end
      end
    end
  end
end
