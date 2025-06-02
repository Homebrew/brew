require "rbs"

module TypeProf
  class RBSReader
    def initialize
      @repo = RBS::Repository.new
      collection_path = Config.current.collection_path
      if collection_path&.exist?
        collection_lock = RBS::Collection::Config.lockfile_of(collection_path)
        @repo.add(collection_lock.repo_path)
      end
      @env, @loaded_gems, @builtin_env_json = RBSReader.get_builtin_env
    end

    @builtin_env = @builtin_env_json = nil
    def self.get_builtin_env
      @loaded_gems = []
      unless @builtin_env
        @builtin_env = RBS::Environment.new

        loader = RBS::EnvironmentLoader.new

        # TODO: invalidate this cache when rbs_collection.yml was changed
        collection_path = Config.current.collection_path
        if collection_path&.exist?
          collection_lock = RBS::Collection::Config.lockfile_of(collection_path)
          collection_lock.gems.each {|gem| @loaded_gems << gem["name"] }
          loader.add_collection(collection_lock)
        end

        new_decls = loader.load(env: @builtin_env).map {|decl,| decl }
        @builtin_env_json = load_rbs(@builtin_env, new_decls)
      end

      return @builtin_env.dup, @loaded_gems.dup, @builtin_env_json
    end

    def load_builtin
      @builtin_env_json
    end

    class RBSCollectionDefined < StandardError; end

    def load_library(lib)
      loader = RBS::EnvironmentLoader.new(core_root: nil, repository: @repo)
      if @loaded_gems.include?(lib)
        raise RBSCollectionDefined
      end
      @loaded_gems << lib
      loader.add(library: lib)

      case lib
      when 'bigdecimal-math'
        loader.add(library: 'bigdecimal')
      when "yaml"
        loader.add(library: "pstore")
        loader.add(library: "dbm")
      when "logger"
        loader.add(library: "monitor")
      when "csv"
        loader.add(library: "forwardable")
      when "prime"
        loader.add(library: "singleton")
      end

      new_decls = loader.load(env: @env).map {|decl,| decl }
      RBSReader.load_rbs(@env, new_decls)
    end

    def load_paths(paths)
      loader = RBS::EnvironmentLoader.new(core_root: nil, repository: @repo)
      paths.each {|path| loader.add(path: path) }
      new_decls = loader.load(env: @env).map {|decl,| decl }
      RBSReader.load_rbs(@env, new_decls)
    end

    def load_rbs_string(name, content)
      buffer = RBS::Buffer.new(name: name, content: content)
      new_decls = []
      RBS::Parser.parse_signature(buffer).each do |decl|
        @env << decl
        new_decls << decl
      end
      RBSReader.load_rbs(@env, new_decls)
    end

    def self.load_rbs(env, new_decls)
      all_env = env.resolve_type_names
      resolver = RBS::TypeNameResolver.from_env(all_env)
      cur_env = RBS::Environment.new
      new_decls.each do |decl|
        cur_env << env.resolve_declaration(resolver, decl, outer: [], prefix: RBS::Namespace.root)
      end

      RBS2JSON.new(all_env, cur_env).dump_json
    end
  end

  class RBS2JSON
    def initialize(all_env, cur_env)
      @all_env, @cur_env = all_env, cur_env
      @alias_resolution_stack = {}
    end

    def dump_json
      {
        classes: conv_classes,
        constants: conv_constants,
        globals: conv_globals,
      }
    end

    # constant_name = [Symbol]
    #
    # { constant_name => type }
    def conv_constants
      constants = {}
      @cur_env.constant_decls.each do |name, decl|
        klass = conv_type_name(name)
        constants[klass] = conv_type(decl.decl.type)
      end
      constants
    end

    # gvar_name = Symbol (:$gvar)
    #
    # { gvar_name => type }
    def conv_globals
      gvars = {}
      @cur_env.global_decls.each do |name, decl|
        decl = decl.decl
        gvars[name] = conv_type(decl.type)
      end
      gvars
    end

    def conv_classes
      json = {}

      each_class_decl do |name, decls|
        klass = conv_type_name(name)
        super_class_name, super_class_args = get_super_class(name, decls)
        if super_class_name
          name = conv_type_name(super_class_name)
          type_args = super_class_args.map {|type| conv_type(type) }
          superclass = [name, type_args]
        end

        type_params = nil
        modules = { include: [], extend: [], prepend: [] }
        methods = {}
        attr_methods = {}
        ivars = {}
        cvars = {}
        rbs_sources = {}
        visibility = true

        decls.each do |decl|
          decl = decl.decl

          type_params2 = decl.type_params
          # A hack to deal with the imcompatibility between rbs 1.8 and 2.0
          type_params2 = type_params2.params if type_params2.respond_to?(:params)
          type_params2 = type_params2.map {|param| [param.name, param.variance] }
          raise "inconsistent type parameter declaration" if type_params && type_params != type_params2
          type_params = type_params2

          decl.members.each do |member|
            case member
            when RBS::AST::Members::MethodDefinition
              name = member.name

              method_types = member.types.map do |method_type|
                case method_type
                when RBS::MethodType then method_type
                when :super then raise NotImplementedError
                end
              end

              method_def = conv_method_def(method_types, visibility)
              rbs_source = [
                (member.kind == :singleton ? "self." : "") + member.name.to_s,
                member.types.map {|type| type.location.source },
                [member.location.name, CodeRange.from_rbs(member.location)],
              ]
              if member.instance?
                methods[[false, name]] = method_def
                rbs_sources[[false, name]] = rbs_source
              end
              if member.singleton?
                methods[[true, name]] = method_def
                rbs_sources[[true, name]] = rbs_source
              end
            when RBS::AST::Members::AttrReader
              ty = conv_type(member.type)
              attr_methods[[false, member.name]] = attr_method_def(:reader, member.name, ty, visibility)
              rbs_sources[[false, member.name]] = attr_rbs_source(member)
            when RBS::AST::Members::AttrWriter
              ty = conv_type(member.type)
              attr_methods[[false, member.name]] = attr_method_def(:writer, member.name, ty, visibility)
              rbs_sources[[false, member.name]] = attr_rbs_source(member)
            when RBS::AST::Members::AttrAccessor
              ty = conv_type(member.type)
              attr_methods[[false, member.name]] = attr_method_def(:accessor, member.name, ty, visibility)
              rbs_sources[[false, member.name]] = attr_rbs_source(member)
            when RBS::AST::Members::Alias
              # XXX: an alias to attr methods?
              if member.instance?
                method_def = methods[[false, member.old_name]]
                methods[[false, member.new_name]] = method_def if method_def
              end
              if member.singleton?
                method_def = methods[[true, member.old_name]]
                methods[[true, member.new_name]] = method_def if method_def
              end

            when RBS::AST::Members::Include
              name = member.name
              if name.kind == :class
                # including a module
                mod = conv_type_name(name)
                type_args = member.args.map {|type| conv_type(type) }
                modules[:include] << [mod, type_args]
              else
                # including an interface
                mod = conv_type_name(name)
                type_args = member.args.map {|type| conv_type(type) }
                modules[:include] << [mod, type_args]
              end

            when RBS::AST::Members::Extend
              name = member.name
              if name.kind == :class
                mod = conv_type_name(name)
                type_args = member.args.map {|type| conv_type(type) }
                modules[:extend] << [mod, type_args]
              else
                # extending a module with an interface is not supported yet
              end

            when RBS::AST::Members::Prepend
              name = member.name
              if name.kind == :class
                mod = conv_type_name(name)
                type_args = member.args.map {|type| conv_type(type) }
                modules[:prepend] << [mod, type_args]
              else
                # extending a module with an interface is not supported yet
              end

            when RBS::AST::Members::InstanceVariable
              ivars[member.name] = conv_type(member.type)
            when RBS::AST::Members::ClassVariable
              cvars[member.name] = conv_type(member.type)

            when RBS::AST::Members::Public
              visibility = true
            when RBS::AST::Members::Private
              visibility = false

            # The following declarations are ignoreable because they are handled in other level
            when RBS::AST::Declarations::Constant
            when RBS::AST::Declarations::Alias # type alias
            when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
            when RBS::AST::Declarations::Interface

            else
              warn "Importing #{ member.class.name } is not supported yet"
            end
          end
        end

        json[klass] = {
          type_params: type_params,
          superclass: superclass,
          members: {
            modules: modules,
            methods: methods,
            attr_methods: attr_methods,
            ivars: ivars,
            cvars: cvars,
            rbs_sources: rbs_sources,
          },
        }
      end

      json
    end

    def each_class_decl
      # topological sort
      #   * superclasses and modules appear earlier than their subclasses (Object is earlier than String)
      #   * namespace module appers earlier than its children (Process is earlier than Process::Status)
      visited = {}
      queue = @cur_env.class_decls.keys.map {|name| [:visit, name] }.reverse
      until queue.empty?
        event, name = queue.pop
        case event
        when :visit
          if !visited[name]
            visited[name] = true
            queue << [:new, name]
            @all_env.class_decls[name].decls.each do |decl|
              decl = decl.decl
              next if decl.is_a?(RBS::AST::Declarations::Module)
              each_reference(decl) {|name| queue << [:visit, name] }
            end
            queue << [:visit, name.namespace.to_type_name] if !name.namespace.empty?
          end
        when :new
          decls = @cur_env.class_decls[name]
          yield name, decls.decls if decls
        end
      end

      @cur_env.interface_decls.each do |name, decl|
        yield name, [decl]
      end
    end

    def each_reference(decl, &blk)
      yield decl.name
      if decl.super_class
        name = decl.super_class.name
      else
        name = RBS::BuiltinNames::Object.name
      end
      return if decl.name == RBS::BuiltinNames::BasicObject.name
      return if decl.name == name
      decls = @all_env.class_decls[name]
      if decls
        decls.decls.each do |decl|
          each_reference(decl.decl, &blk)
        end
      end
    end

    def get_super_class(name, decls)
      return nil if name == RBS::BuiltinNames::BasicObject.name

      decls.each do |decl|
        decl = decl.decl
        case decl
        when RBS::AST::Declarations::Class
          super_class = decl.super_class
          return super_class.name, super_class.args if super_class
        when RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface
          return nil
        else
          raise "unknown declaration: %p" % decl.class
        end
      end

      return RBS::BuiltinNames::Object.name, []
    end

    def conv_method_def(rbs_method_types, visibility)
      sig_rets = rbs_method_types.map do |method_type|
        conv_func(method_type.type_params, method_type.type, method_type.block)
      end
      {
        sig_rets: sig_rets,
        visibility: visibility,
      }
    end

    def conv_func(type_params, func, block)
      blk = block ? conv_block(block) : nil

      lead_tys = func.required_positionals.map {|type| conv_type(type.type) }
      opt_tys = func.optional_positionals.map {|type| conv_type(type.type) }
      rest_ty = func.rest_positionals
      rest_ty = conv_type(rest_ty.type) if rest_ty
      opt_kw_tys = func.optional_keywords.to_h {|key, type| [key, conv_type(type.type)] }
      req_kw_tys = func.required_keywords.to_h {|key, type| [key, conv_type(type.type)] }
      rest_kw_ty = func.rest_keywords
      rest_kw_ty = conv_type(rest_kw_ty.type) if rest_kw_ty

      ret_ty = conv_type(func.return_type)

      {
        type_params: type_params,
        lead_tys: lead_tys,
        opt_tys: opt_tys,
        rest_ty: rest_ty,
        req_kw_tys: req_kw_tys,
        opt_kw_tys: opt_kw_tys,
        rest_kw_ty: rest_kw_ty,
        blk: blk,
        ret_ty: ret_ty,
      }
    end

    def attr_method_def(kind, name, ty, visibility)
      {
        kind: kind,
        ivar: name,
        ty: ty,
        visibility: visibility,
      }
    end

    def attr_rbs_source(member)
      [
        member.name.to_s,
        member.type.location.source,
        [member.location.name, CodeRange.from_rbs(member.location)],
      ]
    end

    def conv_block(rbs_block)
      blk = rbs_block.type

      lead_tys = blk.required_positionals.map {|type| conv_type(type.type) }
      opt_tys = blk.optional_positionals.map {|type| conv_type(type.type) }
      rest_ty = blk.rest_positionals
      rest_ty = conv_type(rest_ty.type) if rest_ty
      opt_kw_tys = blk.optional_keywords.to_h {|key, type| [key, conv_type(type.type)] }
      req_kw_tys = blk.required_keywords.to_h {|key, type| [key, conv_type(type.type)] }
      rest_kw_ty = blk.rest_keywords
      rest_kw_ty = conv_type(rest_kw_ty.type) if rest_kw_ty

      ret_ty = conv_type(blk.return_type)

      {
        required_block: rbs_block.required,
        lead_tys: lead_tys,
        opt_tys: opt_tys,
        rest_ty: rest_ty,
        req_kw_tys: req_kw_tys,
        opt_kw_tys: opt_kw_tys,
        rest_kw_ty: rest_kw_ty,
        blk: blk,
        ret_ty: ret_ty,
      }
    end

    def conv_type(ty)
      case ty
      when RBS::Types::ClassSingleton
        [:class, conv_type_name(ty.name)]
      when RBS::Types::ClassInstance
        klass = conv_type_name(ty.name)
        case klass
        when [:Array]
          raise if ty.args.size != 1
          [:array, [:Array], [], conv_type(ty.args.first)]
        when [:Hash]
          raise if ty.args.size != 2
          key, val = ty.args
          [:hash, [:Hash], [conv_type(key), conv_type(val)]]
        when [:Enumerator]
          raise if ty.args.size != 2
          [:array, [:Enumerator], [], conv_type(ty.args.first)]
        else
          if ty.args.empty?
            [:instance, klass]
          else
            [:cell, [:instance, klass], ty.args.map {|ty| conv_type(ty) }]
          end
        end
      when RBS::Types::Bases::Bool   then [:bool]
      when RBS::Types::Bases::Any    then [:any]
      when RBS::Types::Bases::Top    then [:any]
      when RBS::Types::Bases::Void   then [:void]
      when RBS::Types::Bases::Self   then [:self]
      when RBS::Types::Bases::Nil    then [:nil]
      when RBS::Types::Bases::Bottom then [:union, []]
      when RBS::Types::Variable      then [:var, ty.name]
      when RBS::Types::Tuple
        tys = ty.types.map {|ty2| conv_type(ty2) }
        [:array, [:Array], tys, [:union, []]]
      when RBS::Types::Literal
        case ty.literal
        when Integer then [:int]
        when String  then [:str]
        when true    then [:true]
        when false   then [:false]
        when Symbol  then [:sym, ty.literal]
        else
          p ty.literal
          raise NotImplementedError
        end
      when RBS::Types::Alias
        if @alias_resolution_stack[ty.name]
          [:any]
        else
          begin
            @alias_resolution_stack[ty.name] = true
            alias_decl = @all_env.alias_decls[ty.name]
            alias_decl ? conv_type(alias_decl.decl.type) : [:any]
          ensure
            @alias_resolution_stack.delete(ty.name)
          end
        end
      when RBS::Types::Union
        [:union, ty.types.map {|ty2| conv_type(ty2) }.compact]
      when RBS::Types::Intersection
        [:intersection, ty.types.map {|ty2| conv_type(ty2) }.compact]
      when RBS::Types::Optional
        [:optional, conv_type(ty.type)]
      when RBS::Types::Interface
        # XXX: Currently, only a few builtin interfaces are supported
        case ty.to_s
        when "::_ToS" then [:str]
        when "::_ToStr" then [:str]
        when "::_ToInt" then [:int]
        when "::_ToAry[U]" then [:array, [:Array], [], [:var, :U]]
        else
          [:instance, conv_type_name(ty.name)]
        end
      when RBS::Types::Bases::Instance then [:any] # XXX: not implemented yet
      when RBS::Types::Bases::Class then [:any] # XXX: not implemented yet
      when RBS::Types::Record
        [:hash_record, [:Hash], ty.fields.map {|key, ty| [key, conv_type(ty)] }]
      when RBS::Types::Proc
        [:proc, conv_func(nil, ty.type, nil)]
      else
        warn "unknown RBS type: %p" % ty.class
        [:any]
      end
    end

    def conv_type_name(name)
      name.namespace.path + [name.name]
    end
  end

  class Import
    def self.import_builtin(scratch)
      Import.new(scratch, scratch.rbs_reader.load_builtin).import
    end

    def self.import_library(scratch, feature)
      begin
        json = scratch.rbs_reader.load_library(feature)
      rescue RBS::EnvironmentLoader::UnknownLibraryError
        return nil
      rescue RBS::DuplicatedDeclarationError, RBSReader::RBSCollectionDefined
        return true
      end
      # need cache?
      Import.new(scratch, json).import
    end

    def self.import_rbs_files(scratch, rbs_paths)
      rbs_paths = rbs_paths.map {|rbs_path| Pathname(rbs_path) }
      Import.new(scratch, scratch.rbs_reader.load_paths(rbs_paths)).import(true)
    end

    def self.import_rbs_code(scratch, rbs_name, rbs_code)
      Import.new(scratch, scratch.rbs_reader.load_rbs_string(rbs_name, rbs_code)).import(true)
    end

    def initialize(scratch, json)
      @scratch = scratch
      @json = json
    end

    def import(explicit = false)
      classes = @json[:classes].map do |classpath, cdef|
        type_params = cdef[:type_params]
        superclass, superclass_type_args = cdef[:superclass]
        members = cdef[:members]

        name = classpath.last
        superclass = path_to_klass(superclass) if superclass
        base_klass = path_to_klass(classpath[0..-2])

        klass, = @scratch.get_constant(base_klass, name)
        if klass.is_a?(Type::Any)
          klass = @scratch.new_class(base_klass, name, type_params, superclass, nil)

          # There builtin classes are needed to interpret RBS declarations
          case classpath
          when [:NilClass]   then Type::Builtin[:nil]   = klass
          when [:TrueClass]  then Type::Builtin[:true]  = klass
          when [:FalseClass] then Type::Builtin[:false] = klass
          when [:Integer]    then Type::Builtin[:int]   = klass
          when [:String]     then Type::Builtin[:str]   = klass
          when [:Symbol]     then Type::Builtin[:sym]   = klass
          when [:Array]      then Type::Builtin[:ary]   = klass
          when [:Hash]       then Type::Builtin[:hash]  = klass
          when [:Proc]       then Type::Builtin[:proc]  = klass
          end
        end

        [klass, superclass_type_args, members]
      end

      classes.each do |klass, superclass_type_args, members|
        @scratch.add_superclass_type_args!(klass, superclass_type_args&.map {|ty| conv_type(ty) })
        modules = members[:modules]
        methods = members[:methods]
        attr_methods = members[:attr_methods]
        ivars = members[:ivars]
        cvars = members[:cvars]
        rbs_sources = members[:rbs_sources]

        modules.each do |kind, mods|
          mods.each do |mod, type_args|
            type_args = type_args&.map {|ty| conv_type(ty) }
            case kind
            when :include
              @scratch.mix_module(:after, klass, path_to_klass(mod), type_args, false, nil)
            when :extend
              @scratch.mix_module(:after, klass, path_to_klass(mod), type_args, true, nil)
            when :prepend
              @scratch.mix_module(:before, klass, path_to_klass(mod), type_args, false, nil)
            end
          end
        end

        methods.each do |(singleton, method_name), mdef|
          rbs_source = explicit ? rbs_sources[[singleton, method_name]] : nil
          mdef = conv_method_def(method_name, mdef, rbs_source)
          @scratch.add_method(klass, method_name, singleton, mdef)
        end

        attr_methods.each do |(singleton, method_name), mdef|
          rbs_source = explicit ? rbs_sources[[singleton, method_name]] : nil
          ty = conv_type(mdef[:ty]).remove_type_vars
          mdefs = conv_attr_defs(mdef, rbs_source)
          mdefs.each do |mdef|
            @scratch.add_typed_attr_method(klass, mdef)
          end
          @scratch.add_ivar_write!(Type::Instance.new(klass), :"@#{ mdef[:ivar] }", ty, nil)
        end

        ivars.each do |ivar_name, ty|
          ty = conv_type(ty).remove_type_vars
          @scratch.add_ivar_write!(Type::Instance.new(klass), ivar_name, ty, nil)
        end

        cvars.each do |ivar_name, ty|
          ty = conv_type(ty).remove_type_vars
          @scratch.add_cvar_write!(klass, ivar_name, ty, nil)
        end
      end

      @json[:constants].each do |classpath, value|
        base_klass = path_to_klass(classpath[0..-2])
        value = conv_type(value).remove_type_vars
        @scratch.add_constant(base_klass, classpath[-1], value, nil)
      end

      @json[:globals].each do |name, ty|
        ty = conv_type(ty).remove_type_vars
        @scratch.add_gvar_write!(name, ty, nil)
      end

      true
    end

    def conv_method_def(method_name, mdef, rbs_source)
      sig_rets = mdef[:sig_rets].flat_map do |sig_ret|
        conv_func(sig_ret)
      end

      TypedMethodDef.new(sig_rets, rbs_source, mdef[:visibility])
    end

    def conv_attr_defs(mdef, rbs_source)
      ivar = :"@#{ mdef[:ivar] }"
      kind = mdef[:kind]
      pub_meth = mdef[:visibility]

      defs = []
      if kind == :reader || kind == :accessor
        defs << TypedAttrMethodDef.new(ivar, :reader, pub_meth, rbs_source)
      end
      if kind == :writer || kind == :accessor
        defs << TypedAttrMethodDef.new(ivar, :writer, pub_meth, rbs_source)
      end
      raise if defs.empty?
      defs
    end

    def conv_func(sig_ret)
      #type_params = sig_ret[:type_params] # XXX
      lead_tys = sig_ret[:lead_tys]
      opt_tys = sig_ret[:opt_tys]
      rest_ty = sig_ret[:rest_ty]
      req_kw_tys = sig_ret[:req_kw_tys]
      opt_kw_tys = sig_ret[:opt_kw_tys]
      rest_kw_ty = sig_ret[:rest_kw_ty]
      blk = sig_ret[:blk]
      ret_ty = sig_ret[:ret_ty]

      lead_tys = lead_tys.map {|ty| conv_type(ty) }
      opt_tys = opt_tys.map {|ty| conv_type(ty) }
      rest_ty = conv_type(rest_ty) if rest_ty
      kw_tys = []
      req_kw_tys.each {|key, ty| kw_tys << [true, key, conv_type(ty)] }
      opt_kw_tys.each {|key, ty| kw_tys << [false, key, conv_type(ty)] }
      if rest_kw_ty
        ty = conv_type(rest_kw_ty)
        kw_rest_ty = Type.gen_hash do |h|
          k_ty = Type::Instance.new(Type::Builtin[:sym])
          h[k_ty] = ty
        end
      end

      blks = conv_block(blk)

      ret_ty = conv_type(ret_ty)

      blks.map do |blk|
        [MethodSignature.new(lead_tys, opt_tys, rest_ty, [], kw_tys, kw_rest_ty, blk), ret_ty]
      end
    end

    def conv_block(blk)
      return [Type.nil] unless blk

      required_block = blk[:required_block]
      lead_tys = blk[:lead_tys]
      opt_tys = blk[:opt_tys]
      rest_ty = blk[:rest_ty]
      req_kw_tys = blk[:req_kw_tys]
      opt_kw_tys = blk[:opt_kw_tys]
      rest_kw_ty = blk[:rest_kw_ty]
      ret_ty = blk[:ret_ty]

      lead_tys = lead_tys.map {|ty| conv_type(ty) }
      opt_tys = opt_tys.map {|ty| conv_type(ty) }
      rest_ty = conv_type(rest_ty) if rest_ty
      kw_tys = []
      req_kw_tys.each {|key, ty| kw_tys << [true, key, conv_type(ty)] }
      opt_kw_tys.each {|key, ty| kw_tys << [false, key, conv_type(ty)] }
      if rest_kw_ty
        ty = conv_type(rest_kw_ty)
        kw_rest_ty = Type.gen_hash do |h|
          k_ty = Type::Instance.new(Type::Builtin[:sym])
          h[k_ty] = ty
        end
      end

      msig = MethodSignature.new(lead_tys, opt_tys, rest_ty, [], kw_tys, kw_rest_ty, Type.nil)

      ret_ty = conv_type(ret_ty)

      ret = [Type::Proc.new(TypedBlock.new(msig, ret_ty), Type::Builtin[:proc])]
      ret << Type.nil unless required_block
      ret
    end

    def conv_type(ty)
      case ty.first
      when :class then path_to_klass(ty[1])
      when :instance then Type::Instance.new(path_to_klass(ty[1]))
      when :cell
        Type::Cell.new(Type::Cell::Elements.new(ty[2].map {|ty| conv_type(ty) }), conv_type(ty[1]))
      when :any then Type.any
      when :void then Type::Void.new
      when :nil then Type.nil
      when :optional then Type.optional(conv_type(ty[1]))
      when :bool then Type.bool
      when :self then Type::Var.new(:self)
      when :int then Type::Instance.new(Type::Builtin[:int])
      when :str then Type::Instance.new(Type::Builtin[:str])
      when :sym then Type::Symbol.new(ty.last, Type::Instance.new(Type::Builtin[:sym]))
      when :true  then Type::Instance.new(Type::Builtin[:true])
      when :false then Type::Instance.new(Type::Builtin[:false])
      when :array
        _, path, lead_tys, rest_ty = ty
        lead_tys = lead_tys.map {|ty| conv_type(ty) }
        rest_ty = conv_type(rest_ty)
        base_type = Type::Instance.new(path_to_klass(path))
        Type::Array.new(Type::Array::Elements.new(lead_tys, rest_ty), base_type)
      when :hash
        _, path, (k, v) = ty
        Type.gen_hash(Type::Instance.new(path_to_klass(path))) do |h|
          k_ty = conv_type(k)
          v_ty = conv_type(v)
          h[k_ty] = v_ty
        end
      when :hash_record
        _, path, key_tys = ty
        Type.gen_hash(Type::Instance.new(path_to_klass(path))) do |h|
          key_tys.each do |key, ty|
            k_ty = Type::Symbol.new(key, Type::Instance.new(Type::Builtin[:sym]))
            v_ty = conv_type(ty)
            h[k_ty] = v_ty
          end
        end
      when :union
        tys = ty[1]
        Type::Union.create(Utils::Set[*tys.map {|ty2| conv_type(ty2) }], nil) # XXX: Array and Hash support
      when :intersection
        tys = ty[1]
        conv_type(tys.first) # XXX: This is wrong! We need to support intersection type
      when :var
        Type::Var.new(ty[1])
      when :proc
        msig, ret_ty = conv_func(ty[1]).first # Currently, RBS Proc does not accept a block, so the size should be always one
        Type::Proc.new(TypedBlock.new(msig, ret_ty), Type::Instance.new(Type::Builtin[:proc]))
      else
        pp ty
        raise NotImplementedError
      end
    end

    def path_to_klass(path)
      klass = Type::Builtin[:obj]
      path.each do |name|
        klass, = @scratch.get_constant(klass, name)
        if klass == Type.any
          raise TypeProfError.new("A constant `#{ path.join("::") }' is used but not defined in RBS")
        end
      end
      klass
    end
  end
end
