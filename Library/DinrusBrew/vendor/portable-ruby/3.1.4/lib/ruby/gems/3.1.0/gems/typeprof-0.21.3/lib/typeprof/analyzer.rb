module TypeProf
  class CRef
    include Utils::StructuralEquality

    def initialize(outer, klass, singleton)
      @outer = outer
      @klass = klass
      @singleton = singleton
      # flags
      # scope_visi (= method_visi * module_func_flag)
      # refinements
    end

    def extend(klass, singleton)
      CRef.new(self, klass, singleton)
    end

    attr_reader :outer, :klass, :singleton

    def pretty_print(q)
      q.text "CRef["
      q.pp @klass
      q.text "]"
    end
  end

  class Context
    include Utils::StructuralEquality

    def initialize(iseq, cref, mid)
      @iseq = iseq
      @cref = cref
      @mid = mid
    end

    attr_reader :iseq, :cref, :mid

    def source_location(pc)
      if @iseq
        @iseq.source_location(pc)
      else
        "<builtin>"
      end
    end

    def detailed_source_location(pc)
      if @iseq
        @iseq.detailed_source_location(pc)
      else
        nil
      end
    end

    def replace_cref(cref)
      Context.new(@iseq, cref, @mid)
    end
  end

  class TypedContext
    include Utils::StructuralEquality

    def initialize(caller_ep, mid)
      @caller_ep = caller_ep
      @mid = mid
    end

    attr_reader :caller_ep, :mid

    def source_location(_pc)
      if @caller_ep
        @caller_ep.source_location
      else
        "<typed-context:#{ @mid }>"
      end
    end

    def detailed_source_location(_pc)
      if @caller_ep
        @caller_ep.source_location
      else
        nil
      end
    end

    def replace_cref(cref)
      # What to do?
    end
  end

  class ExecutionPoint
    include Utils::StructuralEquality

    def initialize(ctx, pc, outer)
      @ctx = ctx
      @pc = pc
      @outer = outer
    end

    def key
      [@ctx.iseq, @pc]
    end

    attr_reader :ctx, :pc, :outer

    def jump(pc)
      ExecutionPoint.new(@ctx, pc, @outer)
    end

    def next
      ExecutionPoint.new(@ctx, @pc + 1, @outer)
    end

    def replace_cref(cref)
      ExecutionPoint.new(@ctx.replace_cref(cref), @pc, @outer)
    end

    def source_location
      @ctx.source_location(@pc)
    end

    def detailed_source_location
      @ctx.detailed_source_location(@pc)
    end

    def absolute_path
      @ctx.iseq.absolute_path
    end
  end

  class StaticEnv
    include Utils::StructuralEquality

    def initialize(recv_ty, blk_ty, mod_func, pub_meth)
      @recv_ty = recv_ty
      @blk_ty = blk_ty
      @mod_func = mod_func
      @pub_meth = pub_meth

      return if recv_ty == :top #OK
      recv_ty.each_child_global do |ty|
        raise ty.inspect if !ty.is_a?(Type::Instance) && !ty.is_a?(Type::Class) && !ty.is_a?(Type::Symbol) && ty != Type.any
      end
    end

    attr_reader :recv_ty, :blk_ty, :mod_func, :pub_meth

    def merge(other)
      recv_ty = @recv_ty.union(other.recv_ty)
      blk_ty = @blk_ty.union(other.blk_ty)
      mod_func = @mod_func & other.mod_func # ??
      pub_meth = @pub_meth & other.pub_meth # ??
      StaticEnv.new(recv_ty, blk_ty, mod_func, pub_meth)
    end
  end

  class Env
    include Utils::StructuralEquality

    def initialize(static_env, locals, stack, type_params)
      @static_env = static_env
      @locals = locals
      @stack = stack
      @type_params = type_params
    end

    attr_reader :static_env, :locals, :stack, :type_params

    def merge(other)
      raise if @locals.size != other.locals.size
      raise if @stack.size != other.stack.size
      static_env = @static_env.merge(other.static_env)
      locals = []
      @locals.zip(other.locals) {|ty1, ty2| locals << ty1.union(ty2) }
      stack = []
      @stack.zip(other.stack) {|ty1, ty2| stack << ty1.union(ty2) }
      if @type_params
        raise if !other.type_params
        if @type_params == other.type_params
          type_params = @type_params
        else
          type_params = @type_params.internal_hash.dup
          other.type_params.internal_hash.each do |id, elems|
            elems2 = type_params[id]
            if elems2
              if elems != elems2
                type_params[id] = elems.union(elems2)
              end
            else
              type_params[id] = elems
            end
          end
          type_params = Utils::HashWrapper.new(type_params)
        end
      else
        raise if other.type_params
      end
      Env.new(static_env, locals, stack, type_params)
    end

    def push(*tys)
      tys.each do |ty|
        raise "nil cannot be pushed to the stack" if ty.nil?
        ty.each_child do |ty|
          raise if ty.is_a?(Type::Var)
          #raise if ty.is_a?(Type::Instance) && ty.klass.type_params.size > 1
          raise "Array cannot be pushed to the stack" if ty.is_a?(Type::Array)
          raise "Hash cannot be pushed to the stack" if ty.is_a?(Type::Hash)
        end
      end
      Env.new(@static_env, @locals, @stack + tys, @type_params)
    end

    def pop(n)
      stack = @stack.dup
      tys = stack.pop(n)
      nenv = Env.new(@static_env, @locals, stack, @type_params)
      return nenv, tys
    end

    def setn(i, ty)
      stack = Utils.array_update(@stack, -i, ty)
      Env.new(@static_env, @locals, stack, @type_params)
    end

    def topn(i)
      push(@stack[-i - 1])
    end

    def get_local(idx)
      @locals[idx]
    end

    def local_update(idx, ty)
      Env.new(@static_env, Utils.array_update(@locals, idx, ty), @stack, @type_params)
    end

    def get_container_elem_types(id)
      @type_params.internal_hash[id]
    end

    def deploy_type(id, elems)
      type_params = Utils::HashWrapper.new(@type_params.internal_hash.merge({ id => elems }))
      Env.new(@static_env, @locals, @stack, type_params)
    end

    def enable_module_function
      senv = StaticEnv.new(@static_env.recv_ty, @static_env.blk_ty, true, @static_env.pub_meth)
      Env.new(senv, @locals, @stack, @type_params)
    end

    def method_public_set(flag)
      senv = StaticEnv.new(@static_env.recv_ty, @static_env.blk_ty, @static_env.mod_func, flag)
      Env.new(senv, @locals, @stack, @type_params)
    end

    def replace_recv_ty(ty)
      senv = StaticEnv.new(ty, @static_env.blk_ty, @static_env.mod_func, @static_env.pub_meth)
      Env.new(senv, @locals, @stack, @type_params)
    end

    def replace_blk_ty(ty)
      senv = StaticEnv.new(@static_env.recv_ty, ty, @static_env.mod_func, @static_env.pub_meth)
      Env.new(senv, @locals, @stack, @type_params)
    end

    def inspect
      "Env[#{ @static_env.inspect }, locals:#{ @locals.inspect }, stack:#{ @stack.inspect }, type_params:#{ (@type_params&.internal_hash).inspect }]"
    end
  end

  class Scratch
    def inspect
      "#<Scratch>"
    end

    def initialize
      @entrypoints = []

      @worklist = Utils::WorkList.new

      @ep2env = {}

      @class_defs = {}
      @struct_defs = {}

      @iseq_method_to_ctxs = {}

      @alloc_site_to_global_id = {}

      @callsites, @return_envs = {}, {}
      @block_to_ctx = {}
      @method_signatures = {}
      @block_signatures = {}
      @return_values = {}
      @gvar_table = VarTable.new

      @errors = []
      @reveal_types = {}
      @backward_edges = {}

      @pending_execution = {}
      @executed_iseqs = Utils::MutableSet.new

      @loaded_files = {}

      @rbs_reader = RBSReader.new

      @terminated = false

      @anonymous_struct_gen_id = 0

      @types_being_shown = []
      @namespace = nil

      @lsp_completion = nil
      @lsp_signature_help = CodeRangeTable.new
    end

    def add_entrypoint(iseq)
      @entrypoints << iseq
    end

    attr_reader :return_envs, :loaded_files, :rbs_reader

    def get_env(ep)
      @ep2env[ep]
    end

    def merge_env(ep, env)
      # TODO: this is wrong; it include not only proceeds but also indirect propagation like out-of-block variable modification
      #add_edge(ep, @ep)
      env2 = @ep2env[ep]
      if env2
        nenv = env2.merge(env)
        if nenv != env2 && !@worklist.member?(ep)
          @worklist.insert(ep.key, ep)
        end
        @ep2env[ep] = nenv
      else
        @worklist.insert(ep.key, ep)
        @ep2env[ep] = env
      end
    end

    attr_reader :class_defs

    class ClassDef # or ModuleDef
      def initialize(kind, name, absolute_path, superclass)
        raise unless name.is_a?(Array)
        @kind = kind
        @modules = {
          :before => { true => [], false => [] }, # before = include/extend
          :after  => { true => [], false => [] }, # after = prepend
        }
        @name = name
        @consts = {}
        @methods = {}
        @ivars = VarTable.new
        @cvars = VarTable.new
        @absolute_path = absolute_path
        @namespace = nil
        @superclass = superclass
        @subclasses = []
      end

      attr_reader :kind, :modules, :methods, :ivars, :cvars, :absolute_path, :superclass, :subclasses
      attr_accessor :name, :klass_obj

      def mix_module(kind, mod, type_args, singleton, absolute_path)
        mod_, module_type_args, absolute_paths = @modules[kind][singleton].find {|m,| m == mod }
        if mod_
          raise "inconsistent #{ kind == :after ? "include/extend" : "prepend" } type args in RBS?" if module_type_args != type_args && type_args != [] && type_args != nil
        else
          absolute_paths = Utils::MutableSet.new
          @modules[kind][singleton].unshift([mod, type_args, absolute_paths])
        end
        absolute_paths << absolute_path
      end

      def get_constant(name)
        ty, locs = @consts[name]
        ty = ty || Type.any # XXX: warn?
        return ty, locs
      end

      def add_constant(name, ty, def_ep)
        if @consts[name]
          # XXX: warn!
          _, eps = @consts[name]
          @consts[name] = [ty, eps + [def_ep&.detailed_source_location]]
          return
        end
        @consts[name] = [ty, [def_ep&.detailed_source_location]]
      end

      def consts
        @consts.lazy.flat_map do |name, (ty, eps)|
          eps.map do |ep|
            [name, [ty, ep]]
          end
        end
      end

      def add_class_open(name, open_ep)
        ty, eps = @consts[name]
        raise "call this only if the class is opened more than once" if ty.nil?
        @consts[name] = [ty, eps + [open_ep&.detailed_source_location]]
      end


      def adjust_substitution_for_module(mods, mid, mthd, subst, &blk)
        mods.each do |mod_def, type_args,|
          if mod_def.klass_obj.type_params && type_args
            subst2 = {}
            mod_def.klass_obj.type_params.zip(type_args) do |(tyvar, *), tyarg|
              tyvar = Type::Var.new(tyvar)
              subst2[tyvar] = tyarg.substitute(subst, Config.current.options[:type_depth_limit])
            end
            mod_def.adjust_substitution(false, mid, mthd, subst2, false, &blk)
          end
        end
      end

      def adjust_substitution(singleton, mid, mthd, subst, direct, &blk)
        adjust_substitution_for_module(@modules[:before][singleton], mid, mthd, subst, &blk)

        mthds = @methods[[singleton, mid]]
        yield subst, direct if mthds&.include?(mthd)

        adjust_substitution_for_module(@modules[:after][singleton], mid, mthd, subst, &blk)
      end

      def search_method(singleton, mid, visited, &blk)
        # Currently, circular inclusion of modules is allowed
        return if visited[self]
        visited[self] = true

        @modules[:before][singleton].each do |mod_def,|
          mod_def.search_method(false, mid, visited, &blk)
        end

        mthds = @methods[[singleton, mid]]
        yield mthds, @klass_obj, singleton if mthds

        @modules[:after][singleton].each do |mod_def,|
          mod_def.search_method(false, mid, visited, &blk)
        end
      end

      def check_typed(mid, singleton, klass)
        set = @methods[[singleton, mid]]
        return nil unless set
        set = set.select {|mdef| mdef.is_a?(klass) }
        return nil if set.empty?
        return set
      end

      def check_typed_method(mid, singleton)
        check_typed(mid, singleton, TypedMethodDef)
      end

      def check_typed_attr(mid, singleton)
        check_typed(mid, singleton, TypedAttrMethodDef)
      end

      def add_method(mid, singleton, mdef)
        @methods[[singleton, mid]] ||= Utils::MutableSet.new
        @methods[[singleton, mid]] << mdef
        # Need to restart...?
      end

      def set_method(mid, singleton, mdef)
        if mdef
          @methods[[singleton, mid]] = Utils::MutableSet.new
          @methods[[singleton, mid]] << mdef
        else
          @methods.delete([singleton, mid])
        end
      end
    end

    def mix_module(kind, mixing_mod, mixed_mod, type_args, singleton, caller_ep)
      return if mixed_mod == Type.any

      mixing_mod = @class_defs[mixing_mod.idx]
      mixed_mod.each_child do |mixed_mod|
        if mixed_mod.is_a?(Type::Class)
          mixed_mod = @class_defs[mixed_mod.idx]
          if mixed_mod && mixed_mod.kind == :module
            mixing_mod.mix_module(kind, mixed_mod, type_args, singleton, caller_ep ? caller_ep.ctx.iseq.absolute_path : nil)
          else
            warn(caller_ep, "attempted to #{ kind == :after ? "include/extend" : "prepend" } non-module; ignored")
          end
        end
      end
    end

    def cbase_path(cbase)
      cbase && cbase.idx != 1 ? @class_defs[cbase.idx].name : []
    end

    def new_class(cbase, name, type_params, superclass, def_ep)
      show_name = cbase_path(cbase) + [name]
      idx = @class_defs.size
      if superclass
        superclass_def = @class_defs[superclass.idx] unless superclass == :__root__
        @class_defs[idx] = ClassDef.new(:class, show_name, def_ep&.absolute_path, superclass_def)
        superclass_def.subclasses << idx if superclass_def
        klass = Type::Class.new(:class, idx, type_params, superclass, show_name)
        @class_defs[idx].klass_obj = klass
        cbase ||= klass # for bootstrap
        add_constant(cbase, name, klass, def_ep)
        return klass
      else
        # module
        @class_defs[idx] = ClassDef.new(:module, show_name, def_ep&.absolute_path, nil)
        mod = Type::Class.new(:module, idx, type_params, nil, show_name)
        @class_defs[idx].klass_obj = mod
        add_constant(cbase, name, mod, def_ep)
        return mod
      end
    end

    def add_superclass_type_args!(klass, tyargs)
      klass.superclass_type_args = tyargs
    end

    def new_struct(ep)
      return @struct_defs[ep] if @struct_defs[ep]

      idx = @class_defs.size
      superclass = Type::Builtin[:struct]
      name = "AnonymousStruct_generated_#{ @anonymous_struct_gen_id += 1 }"
      # Should we pass a superclass here?
      @class_defs[idx] = ClassDef.new(:class, [name], ep.ctx.iseq.absolute_path, nil)
      #@class_defs[superclass.idx].subclasses << idx # needed?
      klass = Type::Class.new(:class, idx, [], superclass, name)
      add_superclass_type_args!(klass, [Type.any])
      @class_defs[idx].klass_obj = klass

      @struct_defs[ep] = klass

      klass
    end

    attr_accessor :namespace

    def get_class_name(klass)
      if klass == Type.any
        "???"
      else
        path = @class_defs[klass.idx].name
        if @namespace
          i = 0
          i += 1 while @namespace[i] && @namespace[i] == path[i]
          if path[i]
            path[i..].join("::")
          else
            path.last.to_s
          end
        else
          #"::" + path.join("::")
          path.join("::")
        end
      end
    end

    def adjust_substitution(klass, singleton, mid, mthd, subst, &blk)
      direct = true
      if klass.kind == :class
        while klass != :__root__
          class_def = @class_defs[klass.idx]
          class_def.adjust_substitution(singleton, mid, mthd, subst, direct, &blk)
          direct = false
          if klass.superclass && klass.superclass_type_args
            subst2 = {}
            klass.superclass.type_params.zip(klass.superclass_type_args) do |(tyvar, *), tyarg|
              tyvar = Type::Var.new(tyvar)
              subst2[tyvar] = tyarg.substitute(subst, Config.current.options[:type_depth_limit])
            end
            subst = subst2
          end
          klass = klass.superclass
        end
      else
        # module
        class_def = @class_defs[klass.idx]
        class_def.adjust_substitution(singleton, mid, mthd, subst, direct, &blk)
      end
    end

    def traverse_subclasses(klass, &blk)
      @class_defs[klass.idx].subclasses.each do |subclass|
        yield @class_defs[subclass]
        traverse_subclasses(@class_defs[subclass].klass_obj, &blk)
      end
    end

    def search_method(klass, singleton, mid, &blk)
      # XXX: support method alias correctly
      klass_orig = klass
      if klass.kind == :class
        while klass != :__root__
          class_def = @class_defs[klass.idx]
          class_def.search_method(singleton, mid, {}, &blk)
          klass = klass.superclass
        end
      else
        # module
        class_def = @class_defs[klass.idx]
        class_def.search_method(singleton, mid, {}, &blk)
      end
      if singleton
        search_method(Type::Builtin[klass_orig.kind], false, mid, &blk)
      end
    end

    def get_method(klass, singleton, include_subclasses, mid)
      if include_subclasses
        subclasses_mthds = []
        traverse_subclasses(klass) do |subclass|
          subclass.search_method(singleton, mid, {}) do |mthds,|
            subclasses_mthds.concat(mthds.to_a)
          end
        end
        search_method(klass, singleton, mid) {|mthds,| return subclasses_mthds + mthds.to_a }
        return subclasses_mthds
      end

      search_method(klass, singleton, mid) {|mthds,| return mthds }
    end

    def get_all_super_methods(klass, singleton, current_klass, mid)
      hit = false
      search_method(klass, singleton, mid) do |mthds, klass0, singleton0|
        yield mthds, klass0, singleton0 if hit
        hit = klass0 == current_klass
      end
    end

    def get_super_method(ctx, singleton)
      klass = ctx.cref.klass
      mid = ctx.mid
      if klass.kind == :class
        klass = klass.superclass
        while klass != :__root__
          class_def = @class_defs[klass.idx]
          mthd = class_def.get_method(mid, singleton)
          return mthd if mthd
          klass = klass.superclass
        end
      else
        # module
        class_def = @class_defs[klass.idx]
        mthd = class_def.get_method(mid, singleton)
        return mthd if mthd
      end
      nil
    end

    def get_all_methods(klass, singleton, _include_subclasses)
      names = {}

      if klass.kind == :class
        while klass != :__root__
          # TODO: module
          @class_defs[klass.idx].methods.each_key do |singleton0, name|
            if singleton == singleton0
              names[name] = true
            end
          end
          klass = klass.superclass
        end
      else
        @class_defs[klass.idx].methods.each_key do |singleton0, name|
          if singleton == singleton0
            names[name] = true
          end
        end
      end

      names
    end

    def get_constant(klass, name)
      if klass == Type.any
        [Type.any, nil]
      elsif klass.is_a?(Type::Class)
        @class_defs[klass.idx].get_constant(name)
      else
        [Type.any, nil]
      end
    end

    def search_constant(cref, name)
      while cref != :bottom
        ty, locs = get_constant(cref.klass, name)
        return ty, locs if ty != Type.any
        cref = cref.outer
      end

      return Type.any, nil
    end

    def add_constant(klass, name, value, def_ep)
      if klass.is_a?(Type::Class)
        @class_defs[klass.idx].add_constant(name, value, def_ep)
      end
    end

    def check_typed_method(klass, mid, singleton)
      @class_defs[klass.idx].check_typed_method(mid, singleton)
    end

    def check_typed_attr(klass, mid, singleton)
      @class_defs[klass.idx].check_typed_attr(mid, singleton)
    end

    def add_method(klass, mid, singleton, mdef)
      @class_defs[klass.idx].add_method(mid, singleton, mdef)
      mdef
    end

    def set_method(klass, mid, singleton, mdef)
      @class_defs[klass.idx].set_method(mid, singleton, mdef)
      mdef
    end

    def add_attr_method(klass, mid, ivar, kind, pub_meth, ep)
      if kind == :reader || kind == :accessor
        typed_mdef = check_typed_attr(klass, mid, ep.ctx.cref.singleton)
        unless typed_mdef
          add_method(klass, mid, false, ExecutedAttrMethodDef.new(ivar, :reader, pub_meth, ep))
        end
      end
      if kind == :writer || kind == :accessor
        mid = :"#{ mid }="
        typed_mdef = check_typed_attr(klass, mid, ep.ctx.cref.singleton)
        unless typed_mdef
          add_method(klass, mid, false, ExecutedAttrMethodDef.new(ivar, :writer, pub_meth, ep))
        end
      end
    end

    def add_typed_attr_method(klass, mdef)
      name = mdef.ivar[1..-1]
      name = mdef.kind == :writer ? :"#{ name }=" : name.to_sym
      add_method(klass, name, false, mdef)
    end

    def add_iseq_method(klass, mid, iseq, cref, outer_ep, pub_meth)
      add_method(klass, mid, false, ISeqMethodDef.new(iseq, cref, outer_ep, pub_meth))
    end

    def add_singleton_iseq_method(klass, mid, iseq, cref, outer_ep, pub_meth)
      add_method(klass, mid, true, ISeqMethodDef.new(iseq, cref, outer_ep, pub_meth))
    end

    def set_custom_method(klass, mid, impl, pub_meth = true)
      set_method(klass, mid, false, CustomMethodDef.new(impl, pub_meth))
    end

    def set_singleton_custom_method(klass, mid, impl, pub_meth = true)
      set_method(klass, mid, true, CustomMethodDef.new(impl, pub_meth))
    end

    def alias_method(klass, singleton, alias_mid, orig_mid, ep)
      if klass == Type.any
        self
      else
        mdefs = get_method(klass, singleton, false, orig_mid) # XXX: include_subclass == false??
        if mdefs
          # dup is needed for `alias foo foo` (otherwise, "can't add a new key into hash during iteration" error occurs)
          mdefs.dup.each do |mdef|
            @class_defs[klass.idx].add_method(alias_mid, singleton, AliasMethodDef.new(orig_mid, mdef, ep))
          end
        end
      end
    end

    def add_edge(ep, next_ep)
      (@backward_edges[next_ep] ||= {})[ep] = true
    end

    def add_iseq_method_call!(iseq_mdef, ctx)
      @iseq_method_to_ctxs[iseq_mdef] ||= Utils::MutableSet.new
      @iseq_method_to_ctxs[iseq_mdef] << ctx
    end

    def add_executed_iseq(iseq)
      @executed_iseqs << iseq
    end

    def add_callsite!(callee_ctx, caller_ep, caller_env, &ctn)
      if callee_ctx.is_a?(Context)
        @executed_iseqs << callee_ctx.iseq
        callee_type = callee_ctx.iseq.type
        if caller_ep.ctx.is_a?(Context) && (callee_type == :method || callee_type == :block)
          caller_ep.ctx.iseq&.add_called_iseq(caller_ep.pc, callee_ctx.iseq)
        end
      end

      @callsites[callee_ctx] ||= {}
      @callsites[callee_ctx][caller_ep] = ctn
      merge_return_env(caller_ep) {|env| env ? env.merge(caller_env) : caller_env }

      ret_ty = @return_values[callee_ctx] ||= Type.bot
      if ret_ty != Type.bot
        ctn[ret_ty, caller_ep, @return_envs[caller_ep]]
      end
    end

    def add_method_signature!(callee_ctx, msig)
      if @method_signatures[callee_ctx]
        @method_signatures[callee_ctx] = @method_signatures[callee_ctx].merge(msig)
      else
        @method_signatures[callee_ctx] = msig
      end
    end

    def merge_return_env(caller_ep)
      @return_envs[caller_ep] = yield @return_envs[caller_ep]
    end

    def add_return_value!(callee_ctx, ret_ty)
      @return_values[callee_ctx] ||= Type.bot
      @return_values[callee_ctx] = @return_values[callee_ctx].union(ret_ty)

      @callsites[callee_ctx] ||= {}
      @callsites[callee_ctx].each do |caller_ep, ctn|
        ctn[ret_ty, caller_ep, @return_envs[caller_ep]]
      end
    end

    def add_block_to_ctx!(block_body, ctx)
      raise if !block_body.is_a?(Block)
      @block_to_ctx[block_body] ||= Utils::MutableSet.new
      @block_to_ctx[block_body] << ctx
    end

    def add_block_signature!(block_body, bsig)
      if @block_signatures[block_body]
        @block_signatures[block_body] = @block_signatures[block_body].merge(bsig)
      else
        @block_signatures[block_body] = bsig
      end
    end

    class VarTable
      Entry = Struct.new(:rbs_declared, :read_continuations, :type, :absolute_paths, :write_eps)

      def initialize
        @tbl = {}
      end

      def add_read!(site, ep, &ctn)
        entry = @tbl[site] ||= Entry.new(false, {}, Type.bot, Utils::MutableSet.new, Utils::MutableSet.new)
        entry.read_continuations[ep] = ctn
        entry.absolute_paths << ep.ctx.iseq.absolute_path if ep.ctx.is_a?(Context)
        ty = entry.type
        ty = Type.nil if ty == Type.bot
        ctn[ty, ep, entry.write_eps]
      end

      def add_write!(site, ty, ep, scratch)
        entry = @tbl[site] ||= Entry.new(!ep, {}, Type.bot, Utils::MutableSet.new, Utils::MutableSet.new)
        if ep
          if entry.rbs_declared
            unless Type.match?(ty, entry.type)
              scratch.warn(ep, "inconsistent assignment to RBS-declared variable")
              return
            end
          end
          entry.absolute_paths << ep.ctx.iseq.absolute_path
          entry.write_eps << ep
        end
        entry.type = entry.type.union(ty)
        entry.read_continuations.each do |read_ep, ctn|
          ctn[ty, read_ep, ep ? [ep] : []]
        end
      end

      def dump
        @tbl
      end
    end

    def identify_class_for_ivar(recv, var)
      klass, singleton = recv.method_dispatch_info
      return nil unless klass
      search_method(klass, singleton, var) do |mthds, klass0, singleton0|
        if mthds.any? {|mthd| mthd.is_a?(AttrMethodDef) }
          return klass0, singleton
        end
      end
      return klass, singleton
    end

    def get_ivar(recv, var)
      recv = recv.base_type while recv.respond_to?(:base_type)

      klass, singleton = identify_class_for_ivar(recv, var.to_s[1..].to_sym) # search attr_reader

      if klass
        return @class_defs[klass.idx], singleton
      else
        return nil
      end
    end

    def add_ivar_read!(recv, var, ep, &ctn)
      recv.each_child do |recv|
        class_def, singleton = get_ivar(recv, var)
        next unless class_def
        class_def.ivars.add_read!([singleton, var], ep, &ctn)
      end
    end

    def add_ivar_write!(recv, var, ty, ep)
      recv.each_child do |recv|
        class_def, singleton = get_ivar(recv, var)
        next unless class_def
        site = [singleton, var]
        class_def.ivars.add_write!(site, ty, ep, self)
      end
    end

    def add_cvar_read!(klass, var, ep, &ctn)
      klass.each_child do |klass|
        next unless klass.is_a?(Type::Class)
        class_def = @class_defs[klass.idx]
        next unless class_def
        class_def.cvars.add_read!(var, ep, &ctn)
      end
    end

    def add_cvar_write!(klass, var, ty, ep)
      klass.each_child do |klass|
        next unless klass.is_a?(Type::Class)
        class_def = @class_defs[klass.idx]
        next unless class_def
        class_def.cvars.add_write!(var, ty, ep, self)
      end
    end

    def add_gvar_read!(var, ep, &ctn)
      @gvar_table.add_read!(var, ep, &ctn)
    end

    def add_gvar_write!(var, ty, ep)
      @gvar_table.add_write!(var, ty, ep, self)
    end

    def error(ep, msg)
      p [ep.source_location, "[error] " + msg] if Config.current.verbose >= 2
      @errors << [ep, "[error] " + msg]
    end

    def warn(ep, msg)
      p [ep.source_location, "[warning] " + msg] if Config.current.verbose >= 2
      @errors << [ep, "[warning] " + msg]
    end

    def reveal_type(ep, ty)
      key = ep.source_location
      puts "reveal:#{ ep.source_location }:#{ ty.screen_name(self) }" if Config.current.verbose >= 2
      if @reveal_types[key]
        @reveal_types[key] = @reveal_types[key].union(ty)
      else
        @reveal_types[key] = ty
      end
    end

    def get_container_elem_types(env, ep, id)
      if ep.outer
        tmp_ep = ep
        tmp_ep = tmp_ep.outer while tmp_ep.outer
        env = @return_envs[tmp_ep]
      end
      env.get_container_elem_types(id)
    end

    def update_container_elem_types(env, ep, id, base_type)
      if ep.outer
        tmp_ep = ep
        tmp_ep = tmp_ep.outer while tmp_ep.outer
        merge_return_env(tmp_ep) do |menv|
          elems = menv.get_container_elem_types(id)
          elems = yield elems
          menv = menv.deploy_type(id, elems)
          gid = @alloc_site_to_global_id[id]
          if gid
            ty = globalize_type(elems.to_local_type(id, base_type), env, ep)
            add_ivar_write!(*gid, ty, ep)
          end
          menv
        end
        env
      else
        elems = env.get_container_elem_types(id)
        elems = yield elems
        env = env.deploy_type(id, elems)
        gid = @alloc_site_to_global_id[id]
        if gid
          ty = globalize_type(elems.to_local_type(id, base_type), env, ep)
          add_ivar_write!(*gid, ty, ep)
        end
        env
      end
    end

    def get_array_elem_type(env, ep, id, idx = nil)
      elems = get_container_elem_types(env, ep, id)

      if elems
        return elems[idx] || Type.nil if idx
        return elems.squash_or_any
      else
        Type.any
      end
    end

    def get_hash_elem_type(env, ep, id, key_ty = nil)
      elems = get_container_elem_types(env, ep, id)

      if elems
        elems[globalize_type(key_ty, env, ep) || Type.any]
      else
        Type.any
      end
    end

    def type_profile(cancel_token = nil)
      cancel_token ||= Utils::TimerCancelToken.new(Config.current.max_sec)
      tick = Time.now
      iter_counter = 0
      stat_eps = Utils::MutableSet.new

      prologue_ctx = Context.new(nil, nil, nil)
      prologue_ep = ExecutionPoint.new(prologue_ctx, -1, nil)
      prologue_env = Env.new(StaticEnv.new(Type.bot, Type.nil, false, true), [], [], Utils::HashWrapper.new({}))

      until @entrypoints.empty?
        entrypoint = @entrypoints.shift
        if entrypoint.is_a?(String)
          file = entrypoint
          next if @loaded_files[File.expand_path(file)]
          iseq, = ISeq.compile(file)
        else
          iseq = entrypoint
        end

        @loaded_files[iseq.absolute_path] = true
        ep, env = TypeProf.starting_state(iseq)
        merge_env(ep, env)
        add_callsite!(ep.ctx, prologue_ep, prologue_env) {|ty, ep| }

        while true
          until @worklist.empty?
            ep = @worklist.deletemin

            iter_counter += 1
            if Config.current.options[:show_indicator]
              tick2 = Time.now
              if tick2 - tick >= 1
                tick = tick2
                $stderr << "\rType Profiling... (%d instructions @ %s)\e[K" % [iter_counter, ep.source_location]
                $stderr.flush
              end
            end

            if (Config.current.max_iter && Config.current.max_iter <= iter_counter) || cancel_token.cancelled?
              @terminated = true
              break
            end

            stat_eps << ep
            step(ep)
          end

          break if @terminated

          break unless Config.current.options[:stub_execution]

          begin
            iseq, (kind, dummy_continuation) = @pending_execution.first
            break if !iseq
            @pending_execution.delete(iseq)
          end while @executed_iseqs.include?(iseq)

          puts "DEBUG: trigger stub execution (#{ iseq&.name || "(nil)" }): rest #{ @pending_execution.size }" if Config.current.verbose >= 2

          break if !iseq
          case kind
          when :method
            meth, ep, env = dummy_continuation
            merge_env(ep, env)
            add_iseq_method_call!(meth, ep.ctx)

          when :block
            blk, epenvs = dummy_continuation
            epenvs.each do |ep, env|
              merge_env(ep, env)
              add_block_to_ctx!(blk.block_body, ep.ctx)
            end
          end
        end
      end

      $stderr.print "\r\e[K" if Config.current.options[:show_indicator]

      stat_eps
    end

    def report(stat_eps, output)
      Reporters.show_message(@terminated, output)

      Reporters.show_error(@errors, @backward_edges, output)

      Reporters.show_reveal_types(self, @reveal_types, output)

      Reporters.show_gvars(self, @gvar_table, output)

      RubySignatureExporter.new(self, @class_defs, @iseq_method_to_ctxs).show(stat_eps, output)
    end

    def report_lsp
      errs = @errors.map do |ep, msg|
        [ep&.detailed_source_location, msg]
      end

      res = RubySignatureExporter.new(self, @class_defs, @iseq_method_to_ctxs).show_lsp

      path, loc = Config.current.options[:signature_help_loc]
      if path
        sig_help_res = []
        sig_help = @lsp_signature_help[loc]
        if sig_help
          recv = sig_help[:recv]
          mid = sig_help[:mid]
          singleton = sig_help[:singleton]
          mdefs = sig_help[:mdefs]
          node_id = sig_help[:node_id]
          mdefs.each do |mdef|
            case mdef
            when ISeqMethodDef
              ctxs = @iseq_method_to_ctxs[mdef]
              next unless ctxs

              ctx = ctxs.find {|ctx| ctx.mid == mid } || ctxs.first

              method_name = mid
              method_name = "self.#{ method_name }" if singleton

              str = recv.screen_name(self)
              str += singleton ? "." : "#"
              str += method_name.to_s
              str += ": "
              sig, _, sig_help = show_method_signature(ctx)
              offset = str.size
              sig_help = sig_help.transform_values {|r| (r.begin + offset ... r.end + offset) }
              str += sig
              sig_help_res << [str, sig_help, node_id]
            when AliasMethodDef
              # TODO
            when TypedMethodDef
              mdef.rbs_source&.[](1)&.each do |rbs|
                # TODO: sig_help
                sig_help_res << [rbs, {}, node_id]
              end
            end
          end
        end
      end

      {
        sigs: res,
        errors: errs,
        completion: @lsp_completion,
        signature_help: sig_help_res,
      }
    end

    def globalize_type(ty, env, ep)
      if ep.outer
        tmp_ep = ep
        tmp_ep = tmp_ep.outer while tmp_ep.outer
        env = @return_envs[tmp_ep]
      end
      ty.globalize(env, {}, Config.current.options[:type_depth_limit])
    end

    def localize_type(ty, env, ep, alloc_site = AllocationSite.new(ep))
      if ep.outer
        tmp_ep = ep
        tmp_ep = tmp_ep.outer while tmp_ep.outer
        target_env = @return_envs[tmp_ep]
        target_env, ty = ty.localize(target_env, alloc_site, Config.current.options[:type_depth_limit])
        merge_return_env(tmp_ep) do |env|
          env ? env.merge(target_env) : target_env
        end
        return env, ty
      else
        return ty.localize(env, alloc_site, Config.current.options[:type_depth_limit])
      end
    end

    def pend_method_execution(iseq, meth, recv, mid, cref, ep)
      ctx = Context.new(iseq, cref, mid)
      ep = ExecutionPoint.new(ctx, 0, ep)
      locals = [Type.nil] * iseq.locals.size

      fargs_format = iseq.fargs_format
      lead_num = fargs_format[:lead_num] || 0
      post_num = fargs_format[:post_num] || 0
      post_index = fargs_format[:post_start]
      rest_index = fargs_format[:rest_start]
      keyword = fargs_format[:keyword]
      kw_index = fargs_format[:kwbits] - keyword.size if keyword
      kwrest_index = fargs_format[:kwrest]
      block_index = fargs_format[:block_start]
      opt = fargs_format[:opt] || [0]

      (lead_num + opt.size - 1).times {|i| locals[i] = Type.any }
      post_num.times {|i| locals[i + post_index] = Type.any } if post_index
      locals[rest_index] = Type.any if rest_index
      if keyword
        keyword.each_with_index do |kw, i|
          case
          when kw.is_a?(Symbol) # required keyword
            locals[kw_index + i] = Type.any
          when kw.size == 2 # optional keyword (default value is a literal)
            _key, default_ty = *kw
            default_ty = Type.guess_literal_type(default_ty)
            default_ty = default_ty.base_type if default_ty.is_a?(Type::Literal)
            locals[kw_index + i] = default_ty.union(Type.any)
          else # optional keyword (default value is an expression)
            locals[kw_index + i] = Type.any
          end
        end
      end
      locals[kwrest_index] = Type.any if kwrest_index
      locals[block_index] = Type.nil if block_index

      env = Env.new(StaticEnv.new(recv, Type.nil, false, true), locals, [], Utils::HashWrapper.new({}))

      if !@pending_execution[iseq] || @pending_execution[iseq][0] == :block
        @pending_execution[iseq] = [:method, [meth, ep, env]]
      end
    end

    def pend_block_dummy_execution(blk, iseq, nep, nenv)
      @pending_execution[iseq] ||= [:block, [blk, {}]]
      if @pending_execution[iseq][0] == :block
        if @pending_execution[iseq][1][1][nep]
          @pending_execution[iseq][1][1][nep] = @pending_execution[iseq][1][1][nep].merge(nenv)
        else
          @pending_execution[iseq][1][1][nep] = nenv
        end
      else
        # XXX: what to do?
      end
    end

    def get_instance_variable(recv, var, ep, env)
      add_ivar_read!(recv, var, ep) do |ty, ep, write_eps|
        alloc_site = AllocationSite.new(ep)
        nenv, ty = localize_type(ty, env, ep, alloc_site)
        case ty
        when Type::Local
          @alloc_site_to_global_id[ty.id] = [recv, var] # need overwrite check??
        end
        write_eps.each do |write_ep|
          ep.ctx.iseq.add_def_loc(ep.pc, write_ep.detailed_source_location)
        end
        yield ty, nenv
      end
    end

    def set_instance_variable(recv, var, ty, ep, env)
      ty = globalize_type(ty, env, ep)
      add_ivar_write!(recv, var, ty, ep)
    end

    def step(ep)
      env = @ep2env[ep]
      raise "nil env" unless env

      insn = ep.ctx.iseq.insns[ep.pc]
      operands = insn.operands

      if Config.current.verbose >= 2
        # XXX: more dedicated output
        puts "DEBUG: stack=%p" % [env.stack]
        puts "DEBUG: %s (%s) PC=%d insn=%s sp=%d" % [ep.source_location, ep.ctx.iseq.name, ep.pc, insn.insn, env.stack.size]
      end

      case insn.insn
      when :_iseq_body_start
        # XXX: reconstruct and record the method signature
        iseq = ep.ctx.iseq
        lead_num = iseq.fargs_format[:lead_num] || 0
        opt = iseq.fargs_format[:opt] || [0]
        rest_start = iseq.fargs_format[:rest_start]
        post_start = iseq.fargs_format[:post_start]
        post_num = iseq.fargs_format[:post_num] || 0
        kw_start = iseq.fargs_format[:kwbits]
        keyword = iseq.fargs_format[:keyword]
        kw_start -= keyword.size if kw_start
        kw_rest = iseq.fargs_format[:kwrest]
        block_start = iseq.fargs_format[:block_start]

        lead_tys = env.locals[0, lead_num].map {|ty| globalize_type(ty, env, ep) }
        opt_tys = opt.size > 1 ? env.locals[lead_num, opt.size - 1].map {|ty| globalize_type(ty, env, ep) } : []
        if rest_start # XXX:squash
          ty = globalize_type(env.locals[rest_start], env, ep)
          rest_ty = Type.bot
          ty.each_child_global do |ty|
            if ty.is_a?(Type::Array)
              rest_ty = rest_ty.union(ty.elems.squash)
            else
              # XXX: to_ary?
              rest_ty = rest_ty.union(ty)
            end
          end
        end
        post_tys = (post_start ? env.locals[post_start, post_num] : []).map {|ty| globalize_type(ty, env, ep) }
        if keyword
          kw_tys = []
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
            ty = env.locals[kw_start + i]
            ty = ty.union(default_ty) if default_ty
            ty = globalize_type(ty, env, ep)
            kw_tys << [req, key, ty]
          end
        end
        kw_rest_ty = globalize_type(env.locals[kw_rest], env, ep) if kw_rest
        kw_rest_ty = nil if kw_rest_ty == Type.nil
        if block_start
          blk_ty = globalize_type(env.locals[block_start], env, ep)
        elsif iseq.type == :method
          blk_ty = env.static_env.blk_ty
        else
          blk_ty = Type.nil
        end
        msig = MethodSignature.new(lead_tys, opt_tys, rest_ty, post_tys, kw_tys, kw_rest_ty, blk_ty)
        add_method_signature!(ep.ctx, msig)
      when :putspecialobject
        kind, = operands
        ty = case kind
        when 1 then Type::Instance.new(Type::Builtin[:vmcore])
        when 2, 3 # CBASE / CONSTBASE
          ep.ctx.cref.klass
        else
          raise NotImplementedError, "unknown special object: #{ type }"
        end
        env = env.push(ty)
      when :putnil
        env = env.push(Type.nil)
      when :putobject, :duparray
        obj, = operands
        env, ty = localize_type(Type.guess_literal_type(obj), env, ep)
        env = env.push(ty)
      when :putstring
        str, = operands
        ty = Type::Literal.new(str, Type::Instance.new(Type::Builtin[:str]))
        env = env.push(ty)
      when :putself
        ty = env.static_env.recv_ty
        if ty.is_a?(Type::Instance)
          klass = ty.klass
          if klass.type_params.size >= 1
            ty = Type::ContainerType.create_empty_instance(klass)
            env, ty = localize_type(ty, env, ep, AllocationSite.new(ep))
          else
            ty = Type::Instance.new(klass)
          end
          env, ty = localize_type(ty, env, ep)
        end
        env = env.push(ty)
      when :newarray, :newarraykwsplat
        len, = operands
        env, elems = env.pop(len)
        ty = Type::Array.new(Type::Array::Elements.new(elems), Type::Instance.new(Type::Builtin[:ary]))
        env, ty = localize_type(ty, env, ep)
        env = env.push(ty)
      when :newhash
        num, = operands
        env, tys = env.pop(num)

        ty = Type.gen_hash do |h|
          tys.each_slice(2) do |k_ty, v_ty|
            k_ty = globalize_type(k_ty, env, ep)
            h[k_ty] = v_ty
          end
        end

        env, ty = localize_type(ty, env, ep)
        env = env.push(ty)
      when :newhashfromarray
        raise NotImplementedError, "newhashfromarray"
      when :newrange
        env, tys = env.pop(2)
        # XXX: need generics
        env = env.push(Type::Instance.new(Type::Builtin[:range]))

      when :concatstrings
        num, = operands
        env, = env.pop(num)
        env = env.push(Type::Instance.new(Type::Builtin[:str]))
      when :tostring, :anytostring
        env, (_ty1, _ty2,) = env.pop(2)
        env = env.push(Type::Instance.new(Type::Builtin[:str]))
      when :objtostring
        env, (_ty1,) = env.pop(1)
        env = env.push(Type::Instance.new(Type::Builtin[:str]))
      when :freezestring
        # do nothing
      when :toregexp
        _regexp_opt, str_count = operands
        env, tys = env.pop(str_count)
        # TODO: check if tys are all strings?
        env = env.push(Type::Instance.new(Type::Builtin[:regexp]))
      when :intern
        env, (ty,) = env.pop(1)
        # XXX check if ty is String
        env = env.push(Type::Instance.new(Type::Builtin[:sym]))

      when :definemethod
        mid, iseq = operands
        do_define_iseq_method(ep, env, mid, iseq, nil)

      when :definesmethod
        mid, iseq = operands
        env, (recv,) = env.pop(1)
        cref = ep.ctx.cref
        recv.each_child do |recv|
          if recv.is_a?(Type::Class)
            typed_mdef = check_typed_method(recv, mid, true)
            if typed_mdef
              mdef = ISeqMethodDef.new(iseq, cref, nil, env.static_env.pub_meth)
              typed_mdef.each do |typed_mdef|
                typed_mdef.do_match_iseq_mdef(mdef, recv, mid, env, ep, self)
              end
            else
              meth = add_singleton_iseq_method(recv, mid, iseq, cref, nil, env.static_env.pub_meth)
            end

            pend_method_execution(iseq, meth, recv, mid, ep.ctx.cref, nil)
          else
            recv = Type.any # XXX: what to do?
          end
        end
      when :defineclass
        id, iseq, flags = operands
        env, (cbase, superclass) = env.pop(2)
        case flags & 7
        when 0, 2 # CLASS / MODULE
          type = (flags & 7) == 2 ? :module : :class
          existing_klass, = get_constant(cbase, id) # TODO: multiple return values
          if existing_klass.is_a?(Type::Class)
            # record re-opening location
            @class_defs[cbase.idx].add_class_open(id, ep)
            klass = existing_klass
          else
            if existing_klass != Type.any
              error(ep, "the class \"#{ id }\" is #{ existing_klass.screen_name(self) }")
            end
            if type == :class
              if superclass.is_a?(Type::Class)
                # okay
              elsif superclass == Type.any
                warn(ep, "superclass is any; Object is used instead")
                superclass = Type::Builtin[:obj]
              elsif superclass == Type.nil
                superclass = Type::Builtin[:obj]
              elsif superclass.is_a?(Type::Instance)
                warn(ep, "superclass is an instance; Object is used instead")
                superclass = Type::Builtin[:obj]
              else
                warn(ep, "superclass is not a class; Object is used instead")
                superclass = Type::Builtin[:obj]
              end
            else # module
              superclass = nil
            end
            if cbase.is_a?(Type::Class)
              klass = new_class(cbase, id, [], superclass, ep)
              if superclass
                add_superclass_type_args!(klass, superclass.type_params.map { Type.any })

                # inherited hook
                aargs = ActualArguments.new([klass], nil, {}, Type.nil)
                do_send(superclass, :inherited, aargs, ep, env) {|_ret_ty, _ep| }
              end
            else
              klass = Type.any
            end
          end
          singleton = false
        when 1 # SINGLETON_CLASS
          singleton = true
          klass = cbase
          if klass.is_a?(Type::Class)
          elsif klass.is_a?(Type::Any)
          else
            warn(ep, "A singleton class is open for #{ klass.screen_name(self) }; handled as any")
            klass = Type.any
          end
        else
          raise NotImplementedError, "unknown defineclass flag: #{ flags }"
        end
        ncref = ep.ctx.cref.extend(klass, singleton)
        recv = singleton ? Type.any : klass
        blk = env.static_env.blk_ty
        nctx = Context.new(iseq, ncref, nil)
        nep = ExecutionPoint.new(nctx, 0, nil)
        locals = [Type.nil] * iseq.locals.size
        nenv = Env.new(StaticEnv.new(recv, blk, false, true), locals, [], Utils::HashWrapper.new({}))
        merge_env(nep, nenv)
        add_callsite!(nep.ctx, ep, env) do |ret_ty, ep, env|
          nenv, ret_ty = localize_type(ret_ty, env, ep)
          nenv = nenv.push(ret_ty)
          merge_env(ep.next, nenv)
        end
        return
      when :send
        env, recvs, mid, aargs = setup_actual_arguments(:method, operands, ep, env)
        recvs = Type.any if recvs == Type.bot
        do_send(recvs, mid, aargs, ep, env) do |ret_ty, ep, env|
          nenv, ret_ty, = localize_type(ret_ty, env, ep)
          nenv = nenv.push(ret_ty)
          merge_env(ep.next, nenv)
        end
        return
      when :recv_getlocal_send_branch
        getlocal_operands, send_operands, branch_operands = operands
        env, recvs, mid, aargs = setup_actual_arguments(:method, send_operands, ep, env)
        recvs = Type.any if recvs == Type.bot
        recvs.each_child do |recv|
          do_send(recv, mid, aargs, ep, env) do |ret_ty, ep, env|
            env, ret_ty, = localize_type(ret_ty, env, ep)

            branchtype, target, = branch_operands
            # branchtype: :if or :unless or :nil
            ep_then = ep.next
            ep_else = ep.jump(target)

            var_idx, _scope_idx, _escaped = getlocal_operands
            flow_env = env.local_update(-var_idx+2, recv)

            case ret_ty
            when Type::Instance.new(Type::Builtin[:true])
              merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
            when Type::Instance.new(Type::Builtin[:false])
              merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
            else
              merge_env(ep_then, env)
              merge_env(ep_else, env)
            end
          end
        end
        return
      when :arg_getlocal_send_branch
        getlocal_operands, send_operands, branch_operands = operands
        env, recvs, mid, aargs = setup_actual_arguments(:method, send_operands, ep, env)
        raise if aargs.lead_tys.size != 1
        aarg = aargs.lead_tys[0]
        aarg = Type.any if aarg == Type.bot
        recvs.each_child do |recv|
          aarg.each_child do |aarg|
            aargs_tmp = ActualArguments.new([aarg], nil, {}, aargs.blk_ty)
            do_send(recv, mid, aargs_tmp, ep, env) do |ret_ty, ep, env|
              env, ret_ty, = localize_type(ret_ty, env, ep)

              branchtype, target, = branch_operands
              # branchtype: :if or :unless or :nil
              ep_then = ep.next
              ep_else = ep.jump(target)

              var_idx, _scope_idx, _escaped = getlocal_operands
              flow_env = env.local_update(-var_idx+2, aarg)

              case ret_ty
              when Type::Instance.new(Type::Builtin[:true])
                merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
              when Type::Instance.new(Type::Builtin[:false])
                merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
              else
                merge_env(ep_then, env)
                merge_env(ep_else, env)
              end
            end
          end
        end
        return
      when :send_branch
        send_operands, branch_operands = operands
        env, recvs, mid, aargs = setup_actual_arguments(:method, send_operands, ep, env)
        recvs = Type.any if recvs == Type.bot
        do_send(recvs, mid, aargs, ep, env) do |ret_ty, ep, env|
          env, ret_ty, = localize_type(ret_ty, env, ep)

          branchtype, target, = branch_operands
          # branchtype: :if or :unless or :nil
          ep_then = ep.next
          ep_else = ep.jump(target)

          case ret_ty
          when Type::Instance.new(Type::Builtin[:true])
            merge_env(branchtype == :if ? ep_else : ep_then, env)
          when Type::Instance.new(Type::Builtin[:false])
            merge_env(branchtype == :if ? ep_then : ep_else, env)
          else
            merge_env(ep_then, env)
            merge_env(ep_else, env)
          end
        end
        return
      when :invokeblock
        env, recvs, mid, aargs = setup_actual_arguments(:block, operands, ep, env)
        blk = env.static_env.blk_ty
        case
        when blk == Type.nil
          env = env.push(Type.any)
        when blk == Type.any
          #warn(ep, "block is any")
          env = env.push(Type.any)
        else # Proc
          do_invoke_block(blk, aargs, ep, env) do |ret_ty, ep, env|
            nenv, ret_ty, = localize_type(ret_ty, env, ep)
            nenv = nenv.push(ret_ty)
            merge_env(ep.next, nenv)
          end
          return
        end
      when :invokesuper
        env, recv, _, aargs = setup_actual_arguments(:method, operands, ep, env)
        mid = ep.ctx.mid
        found = false
        recv.each_child_global do |recv|
          klass, singleton = recv.method_dispatch_info
          next unless klass
          get_all_super_methods(klass, singleton, ep.ctx.cref.klass, ep.ctx.mid) do |meths, klass|
            found = true
            meths.each do |meth|
              # XXX: this decomposition is really needed??
              # It calls `Object.new` with union receiver which causes an error, but
              # it may be a fault of builtin Object.new implementation.
              meth.do_send(recv, mid, aargs, ep, env, self) do |ret_ty, ep, env|
                nenv, ret_ty, = localize_type(ret_ty, env, ep)
                nenv = nenv.push(ret_ty)
                merge_env(ep.next, nenv)
              end
            end
          end
        end
        return if found
        error(ep, "no superclass method: #{ env.static_env.recv_ty.screen_name(self) }##{ mid }")
        env = env.push(Type.any)
      when :invokebuiltin
        raise NotImplementedError
      when :leave
        if env.stack.size != 1
          raise "stack inconsistency error: #{ env.stack.inspect }"
        end
        env, (ty,) = env.pop(1)
        ty = globalize_type(ty, env, ep)
        add_return_value!(ep.ctx, ty)
        return
      when :throw
        throwtype, = operands
        env, (ty,) = env.pop(1)
        _no_escape = !!(throwtype & 0x8000)
        throwtype = [:none, :return, :break, :next, :retry, :redo][throwtype & 0xff]
        case throwtype
        when :none

        when :return
          ty = globalize_type(ty, env, ep)
          tmp_ep = ep
          tmp_ep = tmp_ep.outer while tmp_ep.outer
          add_return_value!(tmp_ep.ctx, ty)
          return
        when :break
          tmp_ep = ep
          while true
            if tmp_ep.ctx.iseq.type == :block
              tmp_ep = tmp_ep.outer
              nenv = @return_envs[tmp_ep].push(ty)
              merge_env(tmp_ep.next, nenv)
              break
            end
            _type, _iseq, cont, stack_depth = tmp_ep.ctx.iseq.catch_table[tmp_ep.pc]&.find {|type,| type == :break }
            if cont
              nenv = @return_envs[tmp_ep] || env
              nenv, = nenv.pop(nenv.stack.size - stack_depth)
              nenv = nenv.push(ty)
              tmp_ep = tmp_ep.jump(cont)
              merge_env(tmp_ep, nenv)
              break
            end
            tmp_ep = tmp_ep.outer
          end
        when :next, :redo
          # begin; rescue; next; end
          tmp_ep = ep.outer
          _type, _iseq, cont, stack_depth = tmp_ep.ctx.iseq.catch_table[tmp_ep.pc].find {|type,| type == throwtype }
          nenv = @return_envs[tmp_ep]
          nenv, = nenv.pop(nenv.stack.size - stack_depth)
          nenv = nenv.push(ty) if throwtype == :next
          tmp_ep = tmp_ep.jump(cont)
          merge_env(tmp_ep, nenv)
        when :retry
          tmp_ep = ep.outer
          _type, _iseq, cont, stack_depth = tmp_ep.ctx.iseq.catch_table[tmp_ep.pc].find {|type,| type == :retry }
          nenv = @return_envs[tmp_ep]
          nenv, = nenv.pop(nenv.stack.size - stack_depth)
          tmp_ep = tmp_ep.jump(cont)
          merge_env(tmp_ep, nenv)
        else
          p throwtype
          raise NotImplementedError
        end
        return
      when :once
        iseq, = operands

        nctx = Context.new(iseq, ep.ctx.cref, ep.ctx.mid)
        nep = ExecutionPoint.new(nctx, 0, ep)
        raise if iseq.locals != []
        nenv = Env.new(env.static_env, [], [], nil)
        merge_env(nep, nenv)
        add_callsite!(nep.ctx, ep, env) do |ret_ty, ep, env|
          nenv, ret_ty = localize_type(ret_ty, env, ep)
          nenv = nenv.push(ret_ty)
          merge_env(ep.next, nenv)
        end
        return

      when :branch # TODO: check how branchnil is used
        branchtype, target, = operands
        # branchtype: :if or :unless or :nil
        env, (ty,) = env.pop(1)
        ep_then = ep.next
        ep_else = ep.jump(target)

        # TODO: it works for only simple cases: `x = nil; x || 1`
        # It would be good to merge "dup; branchif" to make it context-sensitive-like
        falsy = ty == Type.nil

        merge_env(ep_then, env)
        merge_env(ep_else, env) unless branchtype == :if && falsy
        return
      when :jump
        target, = operands
        merge_env(ep.jump(target), env)
        return

      when :setinstancevariable
        var, = operands
        env, (ty,) = env.pop(1)
        recv = env.static_env.recv_ty
        set_instance_variable(recv, var, ty, ep, env)

      when :getinstancevariable
        var, = operands
        recv = env.static_env.recv_ty
        get_instance_variable(recv, var, ep, env) do |ty, nenv|
          merge_env(ep.next, nenv.push(ty))
        end
        return

      when :setclassvariable
        var, = operands
        env, (ty,) = env.pop(1)
        cbase = ep.ctx.cref.klass
        ty = globalize_type(ty, env, ep)
        # TODO: if superclass has the variable, it should be updated
        add_cvar_write!(cbase, var, ty, ep)

      when :getclassvariable
        var, = operands
        cbase = ep.ctx.cref.klass
        # TODO: if superclass has the variable, it should be read
        add_cvar_read!(cbase, var, ep) do |ty, ep|
          nenv, ty = localize_type(ty, env, ep)
          merge_env(ep.next, nenv.push(ty))
        end
        return

      when :setglobal
        var, = operands
        env, (ty,) = env.pop(1)
        ty = globalize_type(ty, env, ep)
        add_gvar_write!(var, ty, ep)

      when :getglobal
        var, = operands
        ty = Type.builtin_global_variable_type(var)
        if ty
          ty, locs = get_constant(Type::Builtin[:obj], ty) if ty.is_a?(Symbol)
          env, ty = localize_type(ty, env, ep)
          env = env.push(ty)
        else
          add_gvar_read!(var, ep) do |ty, ep|
            nenv, ty = localize_type(ty, env, ep)
            merge_env(ep.next, nenv.push(ty))
          end
          # need to return default nil of global variables
          return
        end

      when :getlocal
        var_idx, scope_idx, _escaped = operands
        if scope_idx == 0
          ty = env.get_local(-var_idx+2)
        else
          tmp_ep = ep
          scope_idx.times do
            tmp_ep = tmp_ep.outer
          end
          ty = @return_envs[tmp_ep].get_local(-var_idx+2)
        end
        env = env.push(ty)
      when :getlocal_branch
        getlocal_operands, branch_operands = operands
        var_idx, _scope_idx, _escaped = getlocal_operands
        ret_ty = env.get_local(-var_idx+2)

        branchtype, target, = branch_operands
        # branchtype: :if or :unless or :nil
        ep_then = ep.next
        ep_else = ep.jump(target)

        var_idx, _scope_idx, _escaped = getlocal_operands

        ret_ty.each_child do |ret_ty|
          flow_env = env.local_update(-var_idx+2, ret_ty)
          case ret_ty
          when Type.any
            merge_env(ep_then, flow_env)
            merge_env(ep_else, flow_env)
          when Type::Instance.new(Type::Builtin[:false]), Type.nil
            merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
          else
            merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
          end
        end
        return
      when :getlocal_dup_branch
        getlocal_operands, _dup_operands, branch_operands = operands
        var_idx, _scope_idx, _escaped = getlocal_operands
        ret_ty = env.get_local(-var_idx+2)

        branchtype, target, = branch_operands
        # branchtype: :if or :unless or :nil
        ep_then = ep.next
        ep_else = ep.jump(target)

        ret_ty.each_child do |ret_ty|
          flow_env = env.local_update(-var_idx+2, ret_ty).push(ret_ty)
          case ret_ty
          when Type.any
            merge_env(ep_then, flow_env)
            merge_env(ep_else, flow_env)
          when Type::Instance.new(Type::Builtin[:false]), Type.nil
            merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
          else
            merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
          end
        end
        return
      when :dup_setlocal_branch
        _dup_operands, setlocal_operands, branch_operands = operands

        env, (ret_ty,) = env.pop(1)

        var_idx, _scope_idx, _escaped = setlocal_operands

        branchtype, target, = branch_operands
        # branchtype: :if or :unless or :nil
        ep_then = ep.next
        ep_else = ep.jump(target)

        ret_ty.each_child do |ret_ty|
          flow_env = env.local_update(-var_idx+2, ret_ty)
          case ret_ty
          when Type.any
            merge_env(ep_then, flow_env)
            merge_env(ep_else, flow_env)
          when Type::Instance.new(Type::Builtin[:false]), Type.nil
            merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
          else
            merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
          end
        end
        return
      when :getlocal_checkmatch_branch
        getlocal_operands, branch_operands = operands
        var_idx, _scope_idx, _escaped = getlocal_operands
        ret_ty = env.get_local(-var_idx+2)

        env, (pattern_ty,) = env.pop(1)

        branchtype, target, = branch_operands
        # branchtype: :if or :unless or :nil
        ep_then = ep.next
        ep_else = ep.jump(target)

        var_idx, _scope_idx, _escaped = getlocal_operands

        ret_ty.each_child do |ret_ty|
          flow_env = env.local_update(-var_idx+2, ret_ty)
          ret_ty = ret_ty.base_type if ret_ty.is_a?(Type::Symbol)
          ret_ty = ret_ty.base_type if ret_ty.is_a?(Type::Local)
          if ret_ty.is_a?(Type::Instance)
            if ret_ty.klass == pattern_ty # XXX: inheritance
              merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
            else
              merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
            end
          else
            merge_env(ep_then, flow_env)
            merge_env(ep_else, flow_env)
          end
        end
        return
      when :setlocal, :setblockparam
        var_idx, scope_idx, _escaped = operands
        env, (ty,) = env.pop(1)
        if scope_idx == 0
          env = env.local_update(-var_idx+2, ty)
        else
          tmp_ep = ep
          scope_idx.times do
            tmp_ep = tmp_ep.outer
          end
          merge_return_env(tmp_ep) do |env|
            env.merge(env.local_update(-var_idx+2, ty))
          end
        end
      when :getconstant
        name, = operands
        env, (cbase, _allow_nil,) = env.pop(2)
        if cbase == Type.nil
          ty, locs = search_constant(ep.ctx.cref, name)
          env, ty = localize_type(ty, env, ep)
          env = env.push(ty)
        elsif cbase == Type.any
          env = env.push(Type.any) # XXX: warning needed?
        else
          ty, locs = get_constant(cbase, name)
          env, ty = localize_type(ty, env, ep)
          env = env.push(ty)
        end
        locs&.each do |loc|
          ep.ctx.iseq.add_def_loc(ep.pc, loc)
        end
      when :setconstant
        name, = operands
        env, (ty, cbase) = env.pop(2)
        old_ty, old_locs = get_constant(cbase, name)
        if old_locs == [nil] # RBS defined
          # TODO: it would be better to check if ty is consistent with old_ty (defined in RBS)
          # instead of extending the type
          env, old_ty = localize_type(globalize_type(old_ty, env, ep), env, ep)
          ty = ty.union(old_ty)
        elsif old_ty != Type.any # XXX???
          warn(ep, "already initialized constant #{ Type::Instance.new(cbase).screen_name(self) }::#{ name }")
        end
        ty.each_child do |ty|
          if ty.is_a?(Type::Class) && cbase.is_a?(Type::Class) && ty.superclass == Type::Builtin[:struct]
            @class_defs[ty.idx].name = cbase_path(cbase) + [name]
          end
        end
        add_constant(cbase, name, globalize_type(ty, env, ep), ep)

      when :getspecial
        key, type = operands
        if type == 0
          case key
          when 0 # VM_SVAR_LASTLINE
            env = env.push(Type.any) # or String | NilClass only?
          when 1 # VM_SVAR_BACKREF ($~)
            merge_env(ep.next, env.push(Type::Instance.new(Type::Builtin[:matchdata])))
            merge_env(ep.next, env.push(Type.nil))
            return
          else # flip-flop
            env = env.push(Type.bool)
          end
        else
          # NTH_REF ($1, $2, ...) / BACK_REF ($&, $+, ...)
          merge_env(ep.next, env.push(Type::Instance.new(Type::Builtin[:str])))
          merge_env(ep.next, env.push(Type.nil))
          return
        end
      when :setspecial
        key, = operands
        if key >= 2 # flip-flop
          env, = env.pop(1)
        else
          raise "unknown setspecial key: #{ key }"
        end

      when :dup
        env, (ty,) = env.pop(1)
        env = env.push(ty).push(ty)
      when :dup_branch
        _dup_operands, branch_operands = operands
        env, (ty,) = env.pop(1)

        branchtype, target, = branch_operands
        # branchtype: :if or :unless or :nil
        ep_then = ep.next
        ep_else = ep.jump(target)

        ty.each_child do |ty|
          flow_env = env.push(ty)
          case ty
          when Type.any
            merge_env(ep_then, flow_env)
            merge_env(ep_else, flow_env)
          when Type::Instance.new(Type::Builtin[:false]), Type.nil
            merge_env(branchtype == :if ? ep_then : ep_else, flow_env)
          else
            merge_env(branchtype == :if ? ep_else : ep_then, flow_env)
          end
        end
        return
      when :duphash
        raw_hash, = operands
        ty = Type.guess_literal_type(raw_hash)
        env, ty = localize_type(globalize_type(ty, env, ep), env, ep)
        env = env.push(ty)
      when :dupn
        n, = operands
        _, tys = env.pop(n)
        tys.each {|ty| env = env.push(ty) }
      when :pop
        env, = env.pop(1)
      when :swap
        env, (a, b) = env.pop(2)
        env = env.push(a).push(b)
      when :reverse
        n, = operands
        env, tys = env.pop(n)
        tys.reverse_each {|ty| env = env.push(ty) }
      when :defined
        env, = env.pop(1)
        sym_ty = Type::Symbol.new(nil, Type::Instance.new(Type::Builtin[:sym]))
        env = env.push(Type.optional(sym_ty))
      when :checkmatch
        flag, = operands

        # This flag means that the stack top is an array, and the check needs to be applied to find all elements
        # However, currently TypeProf uses very conservative interpretation (all check returns both true and false),
        # so we just ignore the flag now
        _array = flag & 4 != 0

        case flag & 3
        when 1 # VM_CHECKMATCH_TYPE_WHEN
          env, = env.pop(2)
          env = env.push(Type.bool)
        when 2 # VM_CHECKMATCH_TYPE_CASE
          env, = env.pop(2)
          env = env.push(Type.bool)
        when 3 # VM_CHECKMATCH_TYPE_RESCUE
          env, = env.pop(2)
          env = env.push(Type.bool)
        else
          raise "unknown checkmatch flag"
        end
      when :checkkeyword
        env = env.push(Type.bool)
      when :adjuststack
        n, = operands
        env, _ = env.pop(n)
      when :nop
      when :setn
        idx, = operands
        if idx >= 1
          env, (ty,) = env.pop(1)
          env = env.setn(idx, ty).push(ty)
        end
      when :topn
        idx, = operands
        env = env.topn(idx)

      when :splatarray
        env, (ty,) = env.pop(1)
        # XXX: vm_splat_array
        env = env.push(ty)
      when :expandarray
        num, flag = operands
        env, (ary,) = env.pop(1)
        splat = flag & 1 == 1
        from_head = flag & 2 == 0
        ary.each_child do |ary|
          case ary
          when Type::Local
            if ary.kind == Type::Array
              elems = get_container_elem_types(env, ep, ary.id)
              elems ||= Type::Array::Elements.new([], Type.any) # XXX
            else
              elems = Type::Array::Elements.new([], Type.any) # XXX
            end
            do_expand_array(ep, env, elems, num, splat, from_head)
          when Type::Any
            nnum = num
            nnum += 1 if splat
            nenv = env
            nnum.times do
              nenv = nenv.push(Type.any)
            end
            add_edge(ep, ep)
            merge_env(ep.next, nenv)
          else
            # TODO: call to_ary (or to_a?)
            elems = Type::Array::Elements.new([ary], Type.bot)
            do_expand_array(ep, env, elems, num, splat, from_head)
          end
        end
        return
      when :concatarray
        env, (ary1, ary2) = env.pop(2)
        if ary1.is_a?(Type::Local) && ary1.kind == Type::Array
          elems1 = get_container_elem_types(env, ep, ary1.id)
          if ary2.is_a?(Type::Local) && ary2.kind == Type::Array
            elems2 = get_container_elem_types(env, ep, ary2.id)
            elems = Type::Array::Elements.new([], elems1.squash.union(elems2.squash))
            env = update_container_elem_types(env, ep, ary1.id, ary1.base_type) { elems }
            env = env.push(ary1)
          else
            elems = Type::Array::Elements.new([], Type.any)
            env = update_container_elem_types(env, ep, ary1.id, ary1.base_type) { elems }
            env = env.push(ary1)
          end
        else
          ty = Type::Array.new(Type::Array::Elements.new([], Type.any), Type::Instance.new(Type::Builtin[:ary]))
          env, ty = localize_type(ty, env, ep)
          env = env.push(ty)
        end

      when :checktype
        kind, = operands
        case kind
        when 5 then klass = :str  # T_STRING
        when 7 then klass = :ary  # T_ARRAY
        when 8 then klass = :hash # T_HASH
        else
          raise NotImplementedError
        end
        env, (val,) = env.pop(1)
        ty = Type.bot
        val.each_child do |val|
        #globalize_type(val, env, ep).each_child_global do |val|
          val = val.base_type while val.respond_to?(:base_type)
          case val
          when Type::Instance.new(Type::Builtin[klass])
            ty = ty.union(Type::Instance.new(Type::Builtin[:true]))
          when Type.any
            ty = Type.bool
          else
            ty = ty.union(Type::Instance.new(Type::Builtin[:false]))
          end
        end
        env = env.push(ty)
      else
        raise "Unknown insn: #{ insn.insn }"
      end

      add_edge(ep, ep)
      merge_env(ep.next, env)

      if ep.ctx.iseq.catch_table[ep.pc]
        ep.ctx.iseq.catch_table[ep.pc].each do |type, iseq, cont, stack_depth|
          next if type != :rescue && type != :ensure
          next if env.stack.size < stack_depth
          cont_ep = ep.jump(cont)
          cont_env, = env.pop(env.stack.size - stack_depth)
          nctx = Context.new(iseq, ep.ctx.cref, ep.ctx.mid)
          nep = ExecutionPoint.new(nctx, 0, cont_ep)
          locals = [Type.nil] * iseq.locals.size
          nenv = Env.new(env.static_env, locals, [], Utils::HashWrapper.new({}))
          merge_env(nep, nenv)
          add_callsite!(nep.ctx, cont_ep, cont_env) do |ret_ty, ep, env|
            nenv, ret_ty = localize_type(ret_ty, env, ep)
            nenv = nenv.push(ret_ty)
            merge_env(ep.jump(cont), nenv)
          end
        end
      end
    end

    private def do_expand_array(ep, env, elems, num, splat, from_head)
      if from_head
        lead_tys, rest_ary_ty = elems.take_first(num)
        if splat
          env, local_ary_ty = localize_type(rest_ary_ty, env, ep)
          env = env.push(local_ary_ty)
        end
        lead_tys.reverse_each do |ty|
          env = env.push(ty)
        end
      else
        rest_ary_ty, following_tys = elems.take_last(num)
        following_tys.each do |ty|
          env = env.push(ty)
        end
        if splat
          env, local_ary_ty = localize_type(rest_ary_ty, env, ep)
          env = env.push(local_ary_ty)
        end
      end
      merge_env(ep.next, env)
    end

    private def setup_actual_arguments(kind, operands, ep, env)
      opt, blk_iseq = operands
      flags = opt[:flag]
      mid = opt[:mid]
      kw_arg = opt[:kw_arg]
      argc = opt[:orig_argc]
      argc += 1 if kind == :method # for the receiver
      argc += kw_arg.size if kw_arg

      flag_args_splat    = flags[ 0] != 0
      flag_args_blockarg = flags[ 1] != 0
      _flag_args_fcall   = flags[ 2] != 0
      _flag_args_vcall   = flags[ 3] != 0
      _flag_args_simple  = flags[ 4] != 0 # unused in TP
      _flag_blockiseq    = flags[ 5] != 0 # unused in VM :-)
      flag_args_kwarg    = flags[ 6] != 0
      flag_args_kw_splat = flags[ 7] != 0
      _flag_tailcall     = flags[ 8] != 0
      _flag_super        = flags[ 9] != 0
      _flag_zsuper       = flags[10] != 0

      argc += 1 if flag_args_blockarg

      env, aargs = env.pop(argc)

      recv = aargs.shift if kind == :method

      if flag_args_blockarg
        blk_ty = aargs.pop
      elsif blk_iseq
        blk_ty = Type::Proc.new(ISeqBlock.new(blk_iseq, ep), Type::Instance.new(Type::Builtin[:proc]))
      else
        blk_ty = Type.nil
      end

      new_blk_ty = Type.bot
      blk_ty.each_child do |blk_ty|
        case blk_ty
        when Type.nil
        when Type.any
        when Type::Proc
        when Type::Symbol
          blk_ty = Type::Proc.new(SymbolBlock.new(blk_ty.sym), Type::Instance.new(Type::Builtin[:proc]))
        else
          # XXX: attempt to call to_proc
          error(ep, "wrong argument type #{ blk_ty.screen_name(self) } (expected Proc)")
          blk_ty = Type.any
        end
        new_blk_ty = new_blk_ty.union(blk_ty)
      end
      blk_ty = new_blk_ty

      if flag_args_splat
        # assert !flag_args_kwarg
        rest_ty = aargs.last
        aargs = aargs[0..-2]
        if flag_args_kw_splat
          # XXX: The types contained in ActualArguments are expected to be all local types.
          # This "globalize_type" breaks the invariant, and violates the assertion of Union#globalize that asserts @elems be nil.
          # To fix this issue fundamentally, ActualArguments should keep all arguments as-is (as like the VM does),
          # and globalize some types on the on-demand bases.
          ty = globalize_type(rest_ty, env, ep)
          if ty.is_a?(Type::Array)
            _, (ty,) = ty.elems.take_last(1)
            case ty
            when Type::Hash
              kw_tys = ty.elems.to_keywords
            when Type::Union
              hash_elems = nil
              ty.elems&.each do |(container_kind, base_type), elems|
                if container_kind == Type::Hash
                  elems.to_keywords
                  hash_elems = hash_elems ? hash_elems.union(elems) : elems
                end
              end
              if hash_elems
                kw_tys = hash_elems.to_keywords
              else
                kw_tys = { nil => Type.any }
              end
            else
              warn(ep, "non hash is passed to **kwarg?") unless ty == Type.any
              kw_tys = { nil => Type.any }
            end
          else
            raise NotImplementedError
          end
        else
          kw_tys = {}
        end
        aargs = ActualArguments.new(aargs, rest_ty, kw_tys, blk_ty)
      elsif flag_args_kw_splat
        last = aargs.last
        # XXX: The types contained in ActualArguments are expected to be all local types.
        # This "globalize_type" breaks the invariant, and violates the assertion of Union#globalize that asserts @elems be nil.
        # To fix this issue fundamentally, ActualArguments should keep all arguments as-is (as like the VM does),
        # and globalize some types on the on-demand bases.
        ty = globalize_type(last, env, ep)
        case ty
        when Type::Hash
          aargs = aargs[0..-2]
          kw_tys = ty.elems.to_keywords
        when Type::Union
          hash_elems = nil
          ty.elems&.each do |(container_kind, base_type), elems|
            if container_kind == Type::Hash
              hash_elems = hash_elems ? hash_elems.union(elems) : elems
            end
          end
          if hash_elems
            kw_tys = hash_elems.to_keywords
          else
            kw_tys = { nil => Type.any }
          end
        when Type::Any
          aargs = aargs[0..-2]
          kw_tys = { nil => Type.any }
        else
          warn(ep, "non hash is passed to **kwarg?")
          kw_tys = { nil => Type.any }
        end
        aargs = ActualArguments.new(aargs, nil, kw_tys, blk_ty)
      elsif flag_args_kwarg
        kw_vals = aargs.pop(kw_arg.size)

        kw_tys = {}
        kw_arg.zip(kw_vals) do |key, v_ty|
          kw_tys[key] = v_ty
        end

        aargs = ActualArguments.new(aargs, nil, kw_tys, blk_ty)
      else
        aargs = ActualArguments.new(aargs, nil, {}, blk_ty)
      end

      if blk_iseq
        # pending dummy execution
        nctx = Context.new(blk_iseq, ep.ctx.cref, ep.ctx.mid)
        nep = ExecutionPoint.new(nctx, 0, ep)
        nlocals = [Type.any] * blk_iseq.locals.size
        nsenv = StaticEnv.new(env.static_env.recv_ty, Type.any, env.static_env.mod_func, env.static_env.pub_meth)
        nenv = Env.new(nsenv, nlocals, [], nil)
        pend_block_dummy_execution(blk_ty, blk_iseq, nep, nenv)
        merge_return_env(ep) {|tenv| tenv ? tenv.merge(env) : env }
      end

      aargs.node_id = opt[:node_id]

      return env, recv, mid, aargs
    end

    def do_send(recvs, mid, aargs, ep, env, &ctn)
      if mid == :__typeprof_lsp_completion
        names = {}
        recvs.each_child do |recv|
          case recv
          when Type::Void, Type::Any
          else
            klass, singleton, include_subclasses = recv.method_dispatch_info
            names.merge!(get_all_methods(klass, singleton, include_subclasses)) if klass
          end
        end
        @lsp_completion = names
        return ctn[Type.any, ep, env]
      end

      recvs.each_child do |recv|
        case recv
        when Type::Void
          error(ep, "void's method is called: #{ globalize_type(recv, env, ep).screen_name(self) }##{ mid }")
          ctn[Type.any, ep, env]
        when Type::Any
          ctn[Type.any, ep, env]
        else
          klass, singleton, include_subclasses = recv.method_dispatch_info
          meths = get_method(klass, singleton, include_subclasses, mid) if klass
          if meths
            path, loc = Config.current.options[:signature_help_loc]
            if path && path == ep.ctx.iseq.path && mid != :inherited # XXX: too ad-hoc!!!
              path, code_range = ep&.detailed_source_location
              if path && code_range&.contain_loc?(loc)
                @lsp_signature_help[code_range] = {
                  recv: recv,
                  mid: mid,
                  singleton: singleton,
                  mdefs: meths,
                  node_id: aargs.node_id,
                }
              end
            end
            meths.each do |meth|
              meth.do_send(recv, mid, aargs, ep, env, self, &ctn)
            end
          else
            meths = get_method(klass, singleton, include_subclasses, :method_missing) if klass
            if meths
              aargs = aargs.for_method_missing(Type::Symbol.new(mid, Type::Instance.new(Type::Builtin[:sym])))
              meths.each do |meth|
                meth.do_send(recv, :method_missing, aargs, ep, env, self, &ctn)
              end
            else
              error(ep, "undefined method: #{ globalize_type(recv, env, ep).screen_name(self) }##{ mid }")
              ctn[Type.any, ep, env]
            end
          end
        end
      end
    end

    def do_invoke_block(blk, aargs, ep, env, replace_recv_ty: nil, replace_cref: nil, &ctn)
      blk.each_child do |blk|
        if blk.is_a?(Type::Proc)
          blk.block_body.do_call(aargs, ep, env, self, replace_recv_ty: replace_recv_ty, replace_cref: replace_cref, &ctn)
        else
          warn(ep, "non-proc is passed as a block") if blk != Type.any
          ctn[Type.any, ep, env]
        end
      end
    end

    def do_define_iseq_method(ep, env, mid, iseq, outer_ep)
      cref = ep.ctx.cref
      if cref.klass.is_a?(Type::Class)
        typed_mdef = check_typed_method(cref.klass, mid, ep.ctx.cref.singleton)
        recv = cref.klass
        recv = Type::Instance.new(recv) unless ep.ctx.cref.singleton
        if typed_mdef
          mdef = ISeqMethodDef.new(iseq, cref, outer_ep, env.static_env.pub_meth)
          typed_mdef.each do |typed_mdef|
            typed_mdef.do_match_iseq_mdef(mdef, recv, mid, env, ep, self)
          end
        else
          if ep.ctx.cref.singleton
            meth = add_singleton_iseq_method(cref.klass, mid, iseq, cref, outer_ep, true)
          else
            meth = add_iseq_method(cref.klass, mid, iseq, cref, outer_ep, env.static_env.pub_meth)
            if env.static_env.mod_func
              add_singleton_iseq_method(cref.klass, mid, iseq, cref, outer_ep, true)
            end
          end
        end

        pend_method_execution(iseq, meth, recv, mid, ep.ctx.cref, outer_ep)
      else
        # XXX: what to do?
      end
    end

    def show_block_signature(blks)
      bsig = nil
      ret_ty = Type.bot

      blks.each do |blk|
        blk.each_child_global do |blk|
          bsig0 = @block_signatures[blk.block_body]
          if bsig0
            if bsig
              bsig = bsig.merge(bsig0)
            else
              bsig = bsig0
            end
          end

          @block_to_ctx[blk.block_body]&.each do |blk_ctx|
            ret_ty = ret_ty.union(@return_values[blk_ctx]) if @return_values[blk_ctx]
          end
        end
      end

      bsig ||= BlockSignature.new([], [], nil, Type.nil)

      bsig, = bsig.screen_name(nil, self)
      ret_ty = ret_ty.screen_name(self)
      ret_ty = (ret_ty.include?("|") ? "(#{ ret_ty })" : ret_ty) # XXX?

      bsig = bsig + " " if bsig != ""
      "{ #{ bsig }-> #{ ret_ty } }"
    end

    def show_proc_signature(blks)
      farg_tys, ret_ty = nil, Type.bot

      blks.each do |blk|
        blk.each_child_global do |blk|
          next if blk.block_body.is_a?(TypedBlock) # XXX: Support TypedBlock
          next unless @block_to_ctx[blk.block_body] # this occurs when screen_name is called before type-profiling finished (e.g., error message)
          @block_to_ctx[blk.block_body].each do |blk_ctx|
            if farg_tys
              if @method_signatures[blk_ctx]
                farg_tys = farg_tys.merge_as_block_arguments(@method_signatures[blk_ctx])
              else
                # this occurs when screen_name is called before type-profiling finished (e.g., error message)
              end
            else
              farg_tys = @method_signatures[blk_ctx]
            end

            ret_ty = ret_ty.union(@return_values[blk_ctx]) if @return_values[blk_ctx]
          end
        end
      end

      return Type.any.screen_name(self) if @types_being_shown.include?(farg_tys) || @types_being_shown.include?(ret_ty)

      begin
        @types_being_shown << farg_tys << ret_ty
        farg_tys, = farg_tys ? farg_tys.screen_name(nil, self) : ["(unknown)"]
        ret_ty = ret_ty.screen_name(self)
        ret_ty = (ret_ty.include?("|") ? "(#{ ret_ty })" : ret_ty) # XXX?

        farg_tys = farg_tys + " " if farg_tys != ""
        "^#{ farg_tys }-> #{ ret_ty }"
      ensure
        @types_being_shown.pop(2)
      end
    end

    def show_method_signature(ctx)
      farg_tys = @method_signatures[ctx]
      return nil unless farg_tys
      ret_ty = ctx.mid == :initialize ? Type::Void.new : @return_values[ctx] || Type.bot

      untyped = farg_tys.include_untyped?(self) || ret_ty.include_untyped?(self)

      farg_tys, ranges = farg_tys.screen_name(ctx.iseq, self)
      ret_ty = ret_ty.screen_name(self)
      ret_ty = (ret_ty.include?("|") ? "(#{ ret_ty })" : ret_ty) # XXX?

      return "#{ (farg_tys.empty? ? "" : "#{ farg_tys } ") }-> #{ ret_ty }", untyped, ranges
    end
  end
end
