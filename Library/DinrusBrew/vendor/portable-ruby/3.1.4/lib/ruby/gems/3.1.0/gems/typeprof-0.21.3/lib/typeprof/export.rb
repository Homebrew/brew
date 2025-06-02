module TypeProf
  module Reporters
    module_function

    def generate_analysis_trace(state, visited, backward_edge)
      return nil if visited[state]
      visited[state] = true
      prev_states = backward_edges[state]
      if prev_states
        prev_states.each_key do |pstate|
          trace = generate_analysis_trace(pstate, visited, backward_edge)
          return [state] + trace if trace
        end
        nil
      else
        []
      end
    end

    def filter_backtrace(trace)
      ntrace = [trace.first]
      trace.each_cons(2) do |ep1, ep2|
        ntrace << ep2 if ep1.ctx != ep2.ctx
      end
      ntrace
    end

    def show_message(terminated, output)
      if Config.current.options[:show_typeprof_version]
        output.puts "# TypeProf #{ VERSION }"
        output.puts
      end
      if terminated
        output.puts "# CAUTION: Type profiling was terminated prematurely because of the limitation"
        output.puts
      end
    end

    def show_error(errors, backward_edge, output)
      return if errors.empty?
      return unless Config.current.options[:show_errors]

      output.puts "# Errors"
      errors.each do |ep, msg|
        if ENV["TP_DETAIL"]
          backtrace = filter_backtrace(generate_analysis_trace(ep, {}, backward_edge))
        else
          backtrace = [ep]
        end
        loc, *backtrace = backtrace.map do |ep|
          ep&.source_location
        end
        output.puts "#{ loc }: #{ msg }"
        backtrace.each do |loc|
          output.puts "        from #{ loc }"
        end
      end
      output.puts
    end

    def show_reveal_types(scratch, reveal_types, output)
      return if reveal_types.empty?

      output.puts "# Revealed types"
      reveal_types.each do |source_location, ty|
        output.puts "#  #{ source_location } #=> #{ ty.screen_name(scratch) }"
      end
      output.puts
    end

    def show_gvars(scratch, gvars, output)
      gvars = gvars.dump.filter_map do |gvar_name, entry|
        if entry.type != Type.bot && !entry.rbs_declared
          [gvar_name, entry]
        end
      end
      # A signature for global variables is not supported in RBS
      return if gvars.empty?

      output.puts "# Global variables"
      gvars.each do |gvar_name, entry|
        output.puts "#{ gvar_name }: #{ entry.type.screen_name(scratch) }"
      end
      output.puts
    end
  end

  class RubySignatureExporter
    def initialize(
      scratch,
      class_defs, iseq_method_to_ctxs
    )
      @scratch = scratch
      @class_defs = class_defs
      @iseq_method_to_ctxs = iseq_method_to_ctxs
    end

    def conv_class(namespace, class_def, inner_classes)
      @scratch.namespace = namespace

      if class_def.klass_obj.superclass != :__root__ && class_def.klass_obj.superclass
        omit = class_def.klass_obj.superclass == Type::Builtin[:obj] || class_def.klass_obj == Type::Builtin[:obj]
        superclass = omit ? nil : @scratch.get_class_name(class_def.klass_obj.superclass)
        type_args = class_def.klass_obj.superclass_type_args
        if type_args && !type_args.empty?
          superclass += "[#{ type_args.map {|ty| ty.screen_name(@scratch) }.join(", ") }]"
        end
      end

      @scratch.namespace = class_def.name

      consts = {}
      class_def.consts.each do |name, (ty, loc)|
        next unless loc
        next if ty.is_a?(Type::Class)
        next if Config.current.check_dir_filter(loc[0]) == :exclude
        consts[name] = ty.screen_name(@scratch)
      end

      modules = class_def.modules.to_h do |kind, mods|
        mods = mods.to_h do |singleton, mods|
          mods = mods.filter_map do |mod_def, _type_args, absolute_paths|
            next if absolute_paths.all? {|path| !path || Config.current.check_dir_filter(path) == :exclude }
            Type::Instance.new(mod_def.klass_obj).screen_name(@scratch)
          end
          [singleton, mods]
        end
        [kind, mods]
      end

      visibilities = {}
      source_locations = {}
      methods = {}
      ivars = class_def.ivars.dump
      cvars = class_def.cvars.dump

      class_def.methods.each do |(singleton, mid), mdefs|
        mdefs.each do |mdef|
          case mdef
          when ISeqMethodDef
            ctxs = @iseq_method_to_ctxs[mdef]
            next unless ctxs

            ctx = ctxs.find {|ctx| ctx.mid == mid } || ctxs.first

            next if Config.current.check_dir_filter(ctx.iseq.absolute_path) == :exclude

            method_name = mid
            method_name = "self.#{ method_name }" if singleton

            key = [:iseq, method_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= ctx.iseq.source_location(0)
            (methods[key] ||= []) << @scratch.show_method_signature(ctx)
          when AliasMethodDef
            next if mdef.def_ep && Config.current.check_dir_filter(mdef.def_ep.source_location) == :exclude
            alias_name, orig_name = mid, mdef.orig_mid
            if singleton
              alias_name = "self.#{ alias_name }"
              orig_name = "self.#{ orig_name }"
            end
            key = [:alias, alias_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= mdef.def_ep&.source_location
            methods[key] = orig_name
          when ExecutedAttrMethodDef
            absolute_path = mdef.def_ep.ctx.iseq.absolute_path
            next if !absolute_path || Config.current.check_dir_filter(absolute_path) == :exclude
            mid = mid.to_s[0..-2].to_sym if mid.to_s.end_with?("=")
            method_name = mid
            method_name = "self.#{ mid }" if singleton
            method_name = [method_name, :"@#{ mid }" != mdef.ivar]
            key = [:attr, method_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= mdef.def_ep.source_location
            if methods[key]
              if methods[key][0] != mdef.kind
                methods[key][0] = :accessor
              end
            else
              entry = ivars[[singleton, mdef.ivar]]
              ty = entry ? entry.type : Type.any
              methods[key] = [mdef.kind, ty.screen_name(@scratch), ty.include_untyped?(@scratch)]
            end
          when TypedMethodDef
            if mdef.rbs_source
              method_name, sigs = mdef.rbs_source
              key = [:rbs, method_name]
              methods[key] = sigs
              visibilities[key] ||= mdef.pub_meth
              source_locations[key] ||= mdef.iseq&.source_location(0)
            end
          when TypedAttrMethodDef
            if mdef.rbs_source
              mid = mid.to_s[0..-2].to_sym if mid.to_s.end_with?("=")
              method_name = mid
              method_name = [method_name, :"@#{ mid }" != mdef.ivar]
              key = [:rbs_attr, method_name]
              visibilities[key] ||= mdef.pub_meth
              if methods[key]
                if methods[key][0] != mdef.kind
                  methods[key][0] = :accessor
                end
              else
                entry = ivars[[singleton, mdef.ivar]]
                ty = entry ? entry.type : Type.any
                methods[key] = [mdef.kind, ty.screen_name(@scratch), ty.include_untyped?(@scratch)]
              end
            end
          end
        end
      end

      superclass_ivars = {}
      while (superclass_def = (superclass_def || class_def).superclass)
        superclass_ivars.merge!(superclass_def.ivars.dump)
      end

      ivars = ivars.map do |(singleton, var), entry|
        next if entry.absolute_paths.all? {|path| Config.current.check_dir_filter(path) == :exclude }
        ty = entry.type
        next unless var.to_s.start_with?("@")

        if (_, existing = superclass_ivars.find {|((s, v), _)| s == singleton && v == var })
          existing_types = existing.type.is_a?(Type::Union) ? existing.type.types : [existing.type]
          entry_types = entry.type.is_a?(Type::Union) ? entry.type.types : [entry.type]
          if entry_types.all? { |t| existing_types.include?(t) }
            # This type is a subset of the parent type
            next
          end
        end

        var = "self.#{ var }" if singleton
        next if methods[[:attr, [singleton ? "self.#{ var.to_s[1..] }" : var.to_s[1..].to_sym, false]]]
        next if entry.rbs_declared
        [var, ty.screen_name(@scratch)]
      end.compact

      cvars = cvars.map do |var, entry|
        next if entry.absolute_paths.all? {|path| Config.current.check_dir_filter(path) == :exclude }
        next if entry.rbs_declared
        [var, entry.type.screen_name(@scratch)]
      end.compact

      if !class_def.absolute_path || Config.current.check_dir_filter(class_def.absolute_path) == :exclude
        if methods.keys.all? {|type,| type == :rbs }
          return nil if consts.empty? && modules[:before][true].empty? && modules[:before][false].empty? && modules[:after][true].empty? && modules[:after][false].empty? && ivars.empty? && cvars.empty? && inner_classes.empty?
        end
      end

      @scratch.namespace = nil

      ClassData.new(
        kind: class_def.kind,
        name: class_def.name,
        superclass: superclass,
        consts: consts,
        modules: modules,
        ivars: ivars,
        cvars: cvars,
        methods: methods,
        visibilities: visibilities,
        source_locations: source_locations,
        inner_classes: inner_classes,
      )
    end

    def conv_class_lsp(namespace, class_def)
      @scratch.namespace = namespace

      if class_def.klass_obj.superclass != :__root__ && class_def.klass_obj.superclass
        omit = class_def.klass_obj.superclass == Type::Builtin[:obj] || class_def.klass_obj == Type::Builtin[:obj]
        superclass = omit ? nil : @scratch.get_class_name(class_def.klass_obj.superclass)
        type_args = class_def.klass_obj.superclass_type_args
        if type_args && !type_args.empty?
          superclass += "[#{ type_args.map {|ty| ty.screen_name(@scratch) }.join(", ") }]"
        end
      end

      @scratch.namespace = class_def.name

      consts = {}
      class_def.consts.each do |name, (ty, loc)|
        next unless loc
        next if ty.is_a?(Type::Class)
        next if Config.current.check_dir_filter(loc[0]) == :exclude
        consts[name] = ty.screen_name(@scratch)
      end

      modules = class_def.modules.to_h do |kind, mods|
        mods = mods.to_h do |singleton, mods|
          mods = mods.filter_map do |mod_def, _type_args, absolute_paths|
            next if absolute_paths.all? {|path| !path || Config.current.check_dir_filter(path) == :exclude }
            Type::Instance.new(mod_def.klass_obj).screen_name(@scratch)
          end
          [singleton, mods]
        end
        [kind, mods]
      end

      visibilities = {}
      source_locations = {}
      methods = {}
      ivars = class_def.ivars.dump
      cvars = class_def.cvars.dump

      class_def.methods.each do |(singleton, mid), mdefs|
        mdefs.each do |mdef|
          case mdef
          when ISeqMethodDef
            ctxs = @iseq_method_to_ctxs[mdef]
            next unless ctxs

            ctx = ctxs.find {|ctx| ctx.mid == mid } || ctxs.first

            next if Config.current.check_dir_filter(ctx.iseq.absolute_path) == :exclude

            method_name = mid
            method_name = "self.#{ method_name }" if singleton

            key = [:iseq, method_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= [ctx.iseq.source_location(0)]
            sig = @scratch.show_method_signature(ctx)
            (methods[key] ||= []) << sig if sig
          when AliasMethodDef
            alias_name, orig_name = mid, mdef.orig_mid
            if singleton
              alias_name = "self.#{ alias_name }"
              orig_name = "self.#{ orig_name }"
            end
            key = [:alias, alias_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= [mdef.def_ep&.source_location]
            methods[key] = orig_name
          when ExecutedAttrMethodDef
            next if !mdef.def_ep
            absolute_path = mdef.def_ep.ctx.iseq.absolute_path
            next if !absolute_path || Config.current.check_dir_filter(absolute_path) == :exclude
            mid = mid.to_s[0..-2].to_sym if mid.to_s.end_with?("=")
            method_name = mid
            method_name = "self.#{ mid }" if singleton
            method_name = [method_name, :"@#{ mid }" != mdef.ivar]
            key = [:attr, method_name]
            visibilities[key] ||= mdef.pub_meth
            source_locations[key] ||= [mdef.def_ep.source_location]
            if methods[key]
              if methods[key][0] != mdef.kind
                methods[key][0] = :accessor
              end
            else
              entry = ivars[[singleton, mdef.ivar]]
              ty = entry ? entry.type : Type.any
              methods[key] = [mdef.kind, ty.screen_name(@scratch), ty.include_untyped?(@scratch)]
            end
          when TypedMethodDef
            if mdef.rbs_source
              method_name, sigs, rbs_code_range = mdef.rbs_source
              key = [:rbs, method_name]
              methods[key] = sigs
              visibilities[key] ||= mdef.pub_meth
              source_locations[key] ||= [mdef.iseq&.source_location(0), rbs_code_range]
            end
          end
        end
      end

      ivars = ivars.map do |(singleton, var), entry|
        next if entry.absolute_paths.all? {|path| Config.current.check_dir_filter(path) == :exclude }
        ty = entry.type
        next unless var.to_s.start_with?("@")
        var = "self.#{ var }" if singleton
        next if methods[[:attr, [singleton ? "self.#{ var.to_s[1..] }" : var.to_s[1..].to_sym, false]]]
        next if entry.rbs_declared
        [var, ty.screen_name(@scratch)]
      end.compact

      cvars = cvars.map do |var, entry|
        next if entry.absolute_paths.all? {|path| Config.current.check_dir_filter(path) == :exclude }
        next if entry.rbs_declared
        [var, entry.type.screen_name(@scratch)]
      end.compact

      if !class_def.absolute_path || Config.current.check_dir_filter(class_def.absolute_path) == :exclude
        if methods.keys.all? {|type,| type == :rbs }
          return nil if consts.empty? && modules[:before][true].empty? && modules[:before][false].empty? && modules[:after][true].empty? && modules[:after][false].empty? && ivars.empty? && cvars.empty?
        end
      end

      @scratch.namespace = nil

      ClassData.new(
        kind: class_def.kind,
        name: class_def.name,
        superclass: superclass,
        consts: consts,
        modules: modules,
        ivars: ivars,
        cvars: cvars,
        methods: methods,
        visibilities: visibilities,
        source_locations: source_locations,
      )
    end

    ClassData = Struct.new(:kind, :name, :superclass, :consts, :modules, :ivars, :cvars, :methods, :visibilities, :source_locations, :inner_classes, keyword_init: true)

    def show_lsp
      res = []
      @class_defs.each_value do |class_def|
        class_data = conv_class_lsp([], class_def)
        next unless class_data
        class_data.methods.each do |key, arg|
          source_location, rbs_code_range = class_data.source_locations[key]
          type, (method_name, hidden) = key
          case type
          when :attr, :rbs_attr
            kind, ty, untyped = *arg
            line = "attr_#{ kind } #{ method_name }#{ hidden ? "()" : "" }: #{ ty }"
          when :rbs
            sigs = arg.sort.join(" | ")
            line = "# def #{ method_name }: #{ sigs }"
          when :iseq
            sigs = []
            untyped = false
            arg.each do |sig, untyped0|
              sigs << sig
              untyped ||= untyped0
            end
            sigs = sigs.sort.join(" | ")
            line = "def #{ method_name }: #{ sigs }"
          when :alias
            orig_name = arg
            line = "alias #{ method_name } #{ orig_name }"
          end
          if source_location =~ /:(\d+)$/
            res << [$`, $1.to_i, line, rbs_code_range, class_data.kind, class_data.name]
          end
        end
      end
      res
    end

    def show(stat_eps, output)
      # make the class hierarchy
      root = {}
      @class_defs.each_value do |class_def|
        h = root
        class_def.name.each do |name|
          h = h[name] ||= {}
        end
        h[:class_def] = class_def
      end

      hierarchy = build_class_hierarchy([], root)

      output.puts "# Classes" # and Modules

      prev_nil = true
      show_class_hierarchy(0, hierarchy).each do |line|
        if line == nil
          output.puts line unless prev_nil
          prev_nil = true
        else
          output.puts line
          prev_nil = false
        end
      end

      if ENV["TP_STAT"]
        output.puts ""
        output.puts "# TypeProf statistics:"
        output.puts "#   %d execution points" % stat_eps.size
      end

      if ENV["TP_COVERAGE"]
        coverage = {}
        stat_eps.each do |ep|
          path = ep.ctx.iseq.path
          lineno = ep.ctx.iseq.insns[ep.pc].lineno - 1
          (coverage[path] ||= [])[lineno] ||= 0
          (coverage[path] ||= [])[lineno] += 1
        end
        File.binwrite("typeprof-analysis-coverage.dump", Marshal.dump(coverage))
      end
    end

    def build_class_hierarchy(namespace, hierarchy)
      hierarchy.map do |name, h|
        class_def = h.delete(:class_def)
        class_data = conv_class(namespace, class_def, build_class_hierarchy(namespace + [name], h))
        class_data
      end.compact
    end

    def show_class_hierarchy(depth, hierarchy)
      lines = []
      hierarchy.each do |class_data|
        lines << nil
        lines.concat show_class_data(depth, class_data)
      end
      lines
    end

    def show_const(namespace, path)
      return path.last.to_s if namespace == path
      i = 0
      i += 1 while namespace[i] && namespace[i] == path[i]
      path[i..].join("::")
    end

    def show_class_data(depth, class_data)
      indent = "  " * depth
      name = class_data.name.last
      superclass = " < " + class_data.superclass if class_data.superclass
      first_line = indent + "#{ class_data.kind } #{ name }#{ superclass }"
      lines = []
      class_data.consts.each do |name, ty|
        lines << (indent + "  #{ name }: #{ ty }")
      end
      class_data.modules.each do |kind, mods|
        mods.each do |singleton, mods|
          case
          when kind == :before &&  singleton then directive = nil
          when kind == :before && !singleton then directive = "prepend"
          when kind == :after  &&  singleton then directive = "extend"
          when kind == :after  && !singleton then directive = "include"
          end
          mods.each do |mod|
            lines << (indent + "  #{ directive } #{ mod }") if directive
          end
        end
      end
      class_data.ivars.each do |var, ty|
        lines << (indent + "  #{ var }: #{ ty }") unless var.start_with?("_")
      end
      class_data.cvars.each do |var, ty|
        lines << (indent + "  #{ var }: #{ ty }")
      end
      lines << nil
      prev_vis = true
      class_data.methods.each do |key, arg|
        vis = class_data.visibilities[key]
        if prev_vis != vis
          lines << nil
          lines << (indent + "  #{ vis ? "public" : "private" }")
          prev_vis = vis
        end
        source_location = class_data.source_locations[key]
        if Config.current.options[:show_source_locations] && source_location
          lines << nil
          lines << (indent + "  # #{ source_location }")
        end
        type, (method_name, hidden) = key
        case type
        when :rbs_attr
          kind, ty, untyped = *arg
          lines << (indent + "# attr_#{ kind } #{ method_name }#{ hidden ? "()" : "" }: #{ ty }")
        when :attr
          kind, ty, untyped = *arg
          exclude = Config.current.options[:exclude_untyped] && untyped ? "#" : " " # XXX
          lines << (indent + "#{ exclude } attr_#{ kind } #{ method_name }#{ hidden ? "()" : "" }: #{ ty }")
        when :rbs
          arg = arg.map { |a| a.split("\n").join("\n" + indent + "#" + " " * (method_name.size + 5)) }
          sigs = arg.sort.join("\n" + indent + "#" + " " * (method_name.size + 5) + "| ")
          lines << (indent + "# def #{ method_name }: #{ sigs }")
        when :iseq
          sigs = []
          untyped = false
          arg.each do |sig, untyped0|
            sigs << sig
            untyped ||= untyped0
          end
          sigs = sigs.sort.join("\n" + indent + " " * (method_name.size + 6) + "| ")
          exclude = Config.current.options[:exclude_untyped] && untyped ? "#" : " " # XXX
          lines << (indent + "#{ exclude } def #{ method_name }: #{ sigs }")
        when :alias
          orig_name = arg
          lines << (indent + "  alias #{ method_name } #{ orig_name }")
        end
      end
      lines.concat show_class_hierarchy(depth + 1, class_data.inner_classes)
      lines.shift until lines.empty? || lines.first
      lines.pop until lines.empty? || lines.last
      lines.unshift first_line
      lines << (indent + "end")
    end
  end
end
