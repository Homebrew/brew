# frozen_string_literal: true
# typed: false

module T::Private::Methods
  @installed_hooks = {}
  if defined?(Concurrent::Hash)
    @signatures_by_method = Concurrent::Hash.new
    @sig_wrappers = Concurrent::Hash.new
  else
    @signatures_by_method = {}
    @sig_wrappers = {}
  end
  @sigs_that_raised = {}
  # stores method names that were declared final without regard for where.
  # enables early rejection of names that we know can't induce final method violations.
  @was_ever_final_names = {}.compare_by_identity
  # maps from a module's object_id to the set of final methods declared in that module.
  # we also overload entries slightly: if the value is nil, that means that the
  # module has final methods somewhere along its ancestor chain, but does not itself
  # have any final methods.
  #
  # we need the latter information to know whether we need to check along the ancestor
  # chain for final method violations.  we need the former information because we
  # care about exactly where a final method is defined (e.g. including the same module
  # twice is permitted).  we could do this with two tables, but it seems slightly
  # cleaner with a single table.
  # Effectively T::Hash[Module, T.nilable(Set))]
  @modules_with_final = Hash.new {|hash, key| hash[key] = nil}.compare_by_identity
  # this stores the old [included, extended] hooks for Module and inherited hook for Class that we override when
  # enabling final checks for when those hooks are called. the 'hooks' here don't have anything to do with the 'hooks'
  # in installed_hooks.
  @old_hooks = nil

  ARG_NOT_PROVIDED = Object.new
  PROC_TYPE = Object.new

  DeclarationBlock = Struct.new(:mod, :loc, :blk, :final, :raw)

  def self.declare_sig(mod, loc, arg, &blk)
    T::Private::DeclState.current.active_declaration = _declare_sig_internal(mod, loc, arg, &blk)

    nil
  end

  # See tests for how to use this.  But you shouldn't be using this.
  def self._declare_sig(mod, arg=nil, &blk)
    _declare_sig_internal(mod, caller_locations(1, 1).first, arg, raw: true, &blk)
  end

  private_class_method def self._declare_sig_internal(mod, loc, arg, raw: false, &blk)
    install_hooks(mod)

    if T::Private::DeclState.current.active_declaration
      T::Private::DeclState.current.reset!
      raise "You called sig twice without declaring a method in between"
    end

    if !arg.nil? && arg != :final
      raise "Invalid argument to `sig`: #{arg}"
    end

    DeclarationBlock.new(mod, loc, blk, arg == :final, raw)
  end

  def self._with_declared_signature(mod, declblock, &blk)
    # If declblock is provided, this code is equivalent to the check in
    # _declare_sig_internal, above.
    # If declblock is not provided and we have an active declaration, we are
    # obviously doing something wrong.
    if T::Private::DeclState.current.active_declaration
      T::Private::DeclState.current.reset!
      raise "You called sig twice without declaring a method in between"
    end
    if declblock
      T::Private::DeclState.current.active_declaration = declblock
    end
    mod.module_exec(&blk)
  end

  def self.start_proc
    DeclBuilder.new(PROC_TYPE, false)
  end

  def self.finalize_proc(decl)
    decl.finalized = true

    if decl.mode != Modes.standard
      raise "Procs cannot have override/abstract modifiers"
    end
    if decl.mod != PROC_TYPE
      raise "You are passing a DeclBuilder as a type. Did you accidentally use `self` inside a `sig` block? Perhaps you wanted the `T.self_type` instead: https://sorbet.org/docs/self-type"
    end
    if decl.returns == ARG_NOT_PROVIDED
      raise "Procs must specify a return type"
    end
    if decl.on_failure != ARG_NOT_PROVIDED
      raise "Procs cannot use .on_failure"
    end

    if decl.params == ARG_NOT_PROVIDED
      decl.params = {}
    end

    T::Types::Proc.new(decl.params, decl.returns)
  end

  # Returns the signature for a method whose definition was preceded by `sig`.
  #
  # @param method [UnboundMethod]
  # @return [T::Private::Methods::Signature]
  def self.signature_for_method(method)
    signature_for_key(method_to_key(method))
  end

  private_class_method def self.signature_for_key(key)
    maybe_run_sig_block_for_key(key)

    # If a subclass Sub inherits a method `foo` from Base, then
    # Sub.instance_method(:foo) != Base.instance_method(:foo) even though they resolve to the
    # same method. Similarly, Foo.method(:bar) != Foo.singleton_class.instance_method(:bar).
    # So, we always do the look up by the method on the owner (Base in this example).
    @signatures_by_method[key]
  end

  # Fetch the directory name of the file that defines the `T::Private` constant and
  # add a trailing slash to allow us to match it as a directory prefix.
  SORBET_RUNTIME_LIB_PATH = File.dirname(T.const_source_location(:Private).first) + File::SEPARATOR
  private_constant :SORBET_RUNTIME_LIB_PATH

  # when target includes a module with instance methods source_method_names, ensure there is zero intersection between
  # the final instance methods of target and source_method_names. so, for every m in source_method_names, check if there
  # is already a method defined on one of target_ancestors with the same name that is final.
  #
  # we assume that source_method_names has already been filtered to only include method
  # names that were declared final at one point.
  def self._check_final_ancestors(target, target_ancestors, source_method_names, source)
    source_ancestors = nil
    # use reverse_each to check farther-up ancestors first, for better error messages.
    target_ancestors.reverse_each do |ancestor|
      final_methods = @modules_with_final.fetch(ancestor, nil)
      # In this case, either ancestor didn't have any final methods anywhere in its
      # ancestor chain, or ancestor did have final methods somewhere in its ancestor
      # chain, but no final methods defined in ancestor itself.  Either way, there
      # are no final methods to check here, so we can move on to the next ancestor.
      next unless final_methods
      source_method_names.each do |method_name|
        next unless final_methods.include?(method_name)

        # If we get here, we are defining a method that some ancestor declared as
        # final.  however, we permit a final method to be defined multiple
        # times if it is the same final method being defined each time.
        if source
          if !source_ancestors
            source_ancestors = source.ancestors
            # filter out things without actual final methods just to make sure that
            # the below checks (which should be uncommon) go as quickly as possible.
            source_ancestors.select! do |a|
              @modules_with_final.fetch(a, nil)
            end
          end
          # final-ness means that there should be no more than one index for which
          # the below block returns true.
          defining_ancestor_idx = source_ancestors.index do |a|
            @modules_with_final.fetch(a).include?(method_name)
          end
          next if defining_ancestor_idx && source_ancestors[defining_ancestor_idx] == ancestor
        end

        definition_file, definition_line = T::Private::Methods.signature_for_method(ancestor.instance_method(method_name)).method.source_location
        is_redefined = target == ancestor
        caller_loc = T::Private::CallerUtils.find_caller {|loc| !loc.path.to_s.start_with?(SORBET_RUNTIME_LIB_PATH)}
        extra_info = "\n"
        if caller_loc
          extra_info = (is_redefined ? "Redefined" : "Overridden") + " here: #{caller_loc.path}:#{caller_loc.lineno}\n"
        end

        error_message = "The method `#{method_name}` on #{ancestor} was declared as final and cannot be " +
                        (is_redefined ? "redefined" : "overridden in #{target}")
        pretty_message = "#{error_message}\n" \
                         "Made final here: #{definition_file}:#{definition_line}\n" \
                         "#{extra_info}"

        begin
          raise pretty_message
        rescue => e
          # sig_validation_error_handler raises by default; on the off chance that
          # it doesn't raise, we need to ensure that the rest of signature building
          # sees a consistent state.  This sig failed to validate, so we should get
          # rid of it.  If we don't do this, errors of the form "You called sig
          # twice without declaring a method in between" will non-deterministically
          # crop up in tests.
          T::Private::DeclState.current.reset!
          T::Configuration.sig_validation_error_handler(e, {})
        end
      end
    end
  end

  def self.add_module_with_final_method(mod, method_name)
    methods = @modules_with_final[mod]
    if methods.nil?
      methods = {}
      @modules_with_final[mod] = methods
    end
    methods[method_name] = true
    nil
  end

  def self.note_module_deals_with_final(mod)
    # Side-effectfully initialize the value if it's not already there
    @modules_with_final[mod]
    @modules_with_final[mod.singleton_class]
  end

  # Only public because it needs to get called below inside the replace_method blocks below.
  def self._on_method_added(hook_mod, mod, method_name)
    if T::Private::DeclState.current.skip_on_method_added
      return
    end

    current_declaration = T::Private::DeclState.current.active_declaration

    if T::Private::Final.final_module?(mod) && (current_declaration.nil? || !current_declaration.final)
      raise "#{mod} was declared as final but its method `#{method_name}` was not declared as final"
    end
    # Don't compute mod.ancestors if we don't need to bother checking final-ness.
    if @was_ever_final_names.include?(method_name) && @modules_with_final.include?(mod)
      _check_final_ancestors(mod, mod.ancestors, [method_name], nil)
      # We need to fetch the active declaration again, as _check_final_ancestors
      # may have reset it (see the comment in that method for details).
      current_declaration = T::Private::DeclState.current.active_declaration
    end

    if current_declaration.nil?
      return
    end
    T::Private::DeclState.current.reset!

    if method_name == :method_added || method_name == :singleton_method_added
      raise(
        "Putting a `sig` on `#{method_name}` is not supported" \
        " (sorbet-runtime uses this method internally to perform `sig` validation logic)"
      )
    end

    original_method = mod.instance_method(method_name)
    sig_block = lambda do
      T::Private::Methods.run_sig(hook_mod, method_name, original_method, current_declaration)
    end

    # Always replace the original method with this wrapper,
    # which is called only on the *first* invocation.
    # This wrapper is very slow, so it will subsequently re-wrap with a much faster wrapper
    # (or unwrap back to the original method).
    key = method_owner_and_name_to_key(mod, method_name)
    unless current_declaration.raw
      T::Private::ClassUtils.replace_method(mod, method_name, true) do |*args, &blk|
        method_sig = T::Private::Methods.maybe_run_sig_block_for_key(key)
        method_sig ||= T::Private::Methods._handle_missing_method_signature(
          self,
          original_method,
          __callee__,
        )

        # Should be the same logic as CallValidation.wrap_method_if_needed but we
        # don't want that extra layer of indirection in the callstack
        if method_sig.mode == T::Private::Methods::Modes.abstract
          # We're in an interface method, keep going up the chain
          if defined?(super)
            super(*args, &blk)
          else
            raise NotImplementedError.new("The method `#{method_sig.method_name}` on #{mod} is declared as `abstract`. It does not have an implementation.")
          end
        # Note, this logic is duplicated (intentionally, for micro-perf) at `CallValidation.wrap_method_if_needed`,
        # make sure to keep changes in sync.
        elsif method_sig.check_level == :always || (method_sig.check_level == :tests && T::Private::RuntimeLevels.check_tests?)
          CallValidation.validate_call(self, original_method, method_sig, args, blk)
        elsif T::Configuration::AT_LEAST_RUBY_2_7
          original_method.bind_call(self, *args, &blk)
        else
          original_method.bind(self).call(*args, &blk) # rubocop:disable Performance/BindCall
        end
      end
    end

    @sig_wrappers[key] = sig_block
    if current_declaration.final
      @was_ever_final_names[method_name] = true
      # use hook_mod, not mod, because for example, we want class C to be marked as having final if we def C.foo as
      # final. change this to mod to see some final_method tests fail.
      note_module_deals_with_final(hook_mod)
      add_module_with_final_method(mod, method_name)
    end
  end

  def self._handle_missing_method_signature(receiver, original_method, callee)
    method_sig = T::Private::Methods.signature_for_method(original_method)
    if !method_sig
      raise "`sig` not present for method `#{callee}` on #{receiver.inspect} but you're trying to run it anyways. " \
        "This should only be executed if you used `alias_method` to grab a handle to a method after `sig`ing it, but that clearly isn't what you are doing. " \
        "Maybe look to see if an exception was thrown in your `sig` lambda or somehow else your `sig` wasn't actually applied to the method."
    end

    if receiver.class <= original_method.owner
      receiving_class = receiver.class
    elsif receiver.singleton_class <= original_method.owner
      receiving_class = receiver.singleton_class
    elsif receiver.is_a?(Module) && receiver <= original_method.owner
      receiving_class = receiver
    else
      raise "#{receiver} is not related to #{original_method} - how did we get here?"
    end

    # Check for a case where `alias` or `alias_method` was called for a
    # method which had already had a `sig` applied. In that case, we want
    # to avoid hitting this slow path again, by moving to a faster validator
    # just like we did or will for the original method.
    #
    # If this isn't an `alias` or `alias_method` case, we're probably in the
    # middle of some metaprogramming using a Method object, e.g. a pattern like
    # `arr.map(&method(:foo))`. There's nothing really we can do to optimize
    # that here.
    receiving_method = receiving_class.instance_method(callee)
    if receiving_method != original_method && receiving_method.original_name == original_method.name
      aliasing_mod = receiving_method.owner
      method_sig = method_sig.as_alias(callee)
      unwrap_method(aliasing_mod, method_sig, original_method)
    end

    method_sig
  end

  # Executes the `sig` block, and converts the resulting Declaration
  # to a Signature.
  def self.run_sig(hook_mod, method_name, original_method, declaration_block)
    current_declaration =
      begin
        run_builder(declaration_block)
      rescue DeclBuilder::BuilderError => e
        T::Configuration.sig_builder_error_handler(e, declaration_block.loc)
        nil
      end

    declaration_block.loc = nil

    signature =
      if current_declaration
        build_sig(hook_mod, method_name, original_method, current_declaration)
      else
        Signature.new_untyped(method: original_method)
      end

    unwrap_method(signature.method.owner, signature, original_method)
    signature
  end

  def self.run_builder(declaration_block)
    builder = DeclBuilder.new(declaration_block.mod, declaration_block.raw)
    builder
      .instance_exec(&declaration_block.blk)
      .finalize!
      .decl
  end

  def self.build_sig(hook_mod, method_name, original_method, current_declaration)
    begin
      # We allow `sig` in the current module's context (normal case) and
      if hook_mod != current_declaration.mod &&
         # inside `class << self`, and
         hook_mod.singleton_class != current_declaration.mod &&
         # on `self` at the top level of a file
         current_declaration.mod != TOP_SELF
        raise "A method (#{method_name}) is being added on a different class/module (#{hook_mod}) than the " \
              "last call to `sig` (#{current_declaration.mod}). Make sure each call " \
              "to `sig` is immediately followed by a method definition on the same " \
              "class/module."
      end

      signature = Signature.new(
        method: original_method,
        method_name: method_name,
        raw_arg_types: current_declaration.params,
        raw_return_type: current_declaration.returns,
        bind: current_declaration.bind,
        mode: current_declaration.mode,
        check_level: current_declaration.checked,
        on_failure: current_declaration.on_failure,
        override_allow_incompatible: current_declaration.override_allow_incompatible,
        defined_raw: current_declaration.raw,
      )

      SignatureValidation.validate(signature)
      signature
    rescue => e
      super_method = original_method&.super_method
      super_signature = signature_for_method(super_method) if super_method

      T::Configuration.sig_validation_error_handler(
        e,
        method: original_method,
        declaration: current_declaration,
        signature: signature,
        super_signature: super_signature
      )

      Signature.new_untyped(method: original_method)
    end
  end

  def self.unwrap_method(mod, signature, original_method)
    maybe_wrapped_method = CallValidation.wrap_method_if_needed(mod, signature, original_method)
    @signatures_by_method[method_to_key(maybe_wrapped_method)] = signature
  end

  def self.has_sig_block_for_method(method)
    has_sig_block_for_key(method_to_key(method))
  end

  private_class_method def self.has_sig_block_for_key(key)
    @sig_wrappers.key?(key)
  end

  def self.maybe_run_sig_block_for_method(method)
    maybe_run_sig_block_for_key(method_to_key(method))
  end

  # Only public so that it can be accessed in the closure for _on_method_added
  def self.maybe_run_sig_block_for_key(key)
    run_sig_block_for_key(key) if has_sig_block_for_key(key)
  end

  def self.run_sig_block_for_method(method)
    run_sig_block_for_key(method_to_key(method))
  end

  private_class_method def self.run_sig_block_for_key(key, force_type_init: false)
    blk = @sig_wrappers[key]
    if !blk
      sig = @signatures_by_method[key]
      if sig
        # We already ran the sig block, perhaps in another thread.
        return sig
      else
        raise "No `sig` wrapper for #{key_to_method(key)}"
      end
    end

    begin
      sig = blk.call
    rescue
      @sigs_that_raised[key] = true
      raise
    end
    if @sigs_that_raised[key]
      raise "A previous invocation of #{key_to_method(key)} raised, and the current one succeeded. Please don't do that."
    end

    @sig_wrappers.delete(key)

    sig.force_type_init if force_type_init

    sig
  end

  def self.run_all_sig_blocks(force_type_init: true)
    loop do
      break if @sig_wrappers.empty?
      key, = @sig_wrappers.first
      run_sig_block_for_key(key, force_type_init: force_type_init)
    end
  end

  def self.all_checked_tests_sigs
    @signatures_by_method.values.select {|sig| sig.check_level == :tests}
  end

  # the module target is adding the methods from the module source to itself. we need to check that for all instance
  # methods M on source, M is not defined on any of target's ancestors.
  def self._hook_impl(target, singleton_class, source)
    # we do not need to call add_was_ever_final here, because we have already marked
    # any such methods when source was originally defined.
    if !@modules_with_final.include?(target)
      if !@modules_with_final.include?(source)
        return
      end
      note_module_deals_with_final(target)
      install_hooks(target)
      return
    end

    methods = source.instance_methods
    methods.select! do |method_name|
      @was_ever_final_names.include?(method_name)
    end
    if methods.empty?
      return
    end

    target_ancestors = singleton_class ? target.singleton_class.ancestors : target.ancestors
    _check_final_ancestors(target, target_ancestors, methods, source)
  end

  def self.set_final_checks_on_hooks(enable)
    is_enabled = !@old_hooks.nil?
    if enable == is_enabled
      return
    end
    if is_enabled
      # A cut-down version of T::Private::ClassUtils::ReplacedMethod#restore, because we
      # should only be resetting final hooks during tests.
      T::Configuration.without_ruby_warnings do
        Module.define_method(:included, @old_hooks[0])
        Module.define_method(:extended, @old_hooks[1])
        Class.define_method(:inherited, @old_hooks[2])
      end
      @old_hooks = nil
    else
      old_included = T::Private::ClassUtils.replace_method(Module, :included, true) do |arg|
        if T::Configuration::AT_LEAST_RUBY_2_7
          old_included.bind_call(self, arg)
        else
          old_included.bind(self).call(arg) # rubocop:disable Performance/BindCall
        end
        ::T::Private::Methods._hook_impl(arg, false, self)
      end
      old_extended = T::Private::ClassUtils.replace_method(Module, :extended, true) do |arg|
        if T::Configuration::AT_LEAST_RUBY_2_7
          old_extended.bind_call(self, arg)
        else
          old_extended.bind(self).call(arg) # rubocop:disable Performance/BindCall
        end
        ::T::Private::Methods._hook_impl(arg, true, self)
      end
      old_inherited = T::Private::ClassUtils.replace_method(Class, :inherited, true) do |arg|
        if T::Configuration::AT_LEAST_RUBY_2_7
          old_inherited.bind_call(self, arg)
        else
          old_inherited.bind(self).call(arg) # rubocop:disable Performance/BindCall
        end
        ::T::Private::Methods._hook_impl(arg, false, self)
      end
      @old_hooks = [old_included, old_extended, old_inherited]
    end
  end

  module MethodHooks
    def method_added(name)
      super(name)
      ::T::Private::Methods._on_method_added(self, self, name)
    end
  end

  module SingletonMethodHooks
    def singleton_method_added(name)
      super(name)
      ::T::Private::Methods._on_method_added(self, singleton_class, name)
    end
  end

  def self.install_hooks(mod)
    return if @installed_hooks.include?(mod)
    @installed_hooks[mod] = true

    if mod == TOP_SELF
      # self at the top-level of a file is weirdly special in Ruby
      # The Ruby VM on startup creates an `Object.new` and stashes it.
      # Unlike when we're using sig inside a module, `self` is actually a
      # normal object, not an instance of Module.
      #
      # Thus we can't ask things like mod.singleton_class? (since that's
      # defined only on Module, not on Object) and even if we could, the places
      # where we need to install the hooks are special.
      mod.extend(SingletonMethodHooks) # def self.foo; end (at top level)
      Object.extend(MethodHooks)       # def foo; end      (at top level)
      return
    end

    # See https://github.com/sorbet/sorbet/pull/3964 for an explanation of why this
    # check (which theoretically should not be needed) is actually needed.
    if !mod.is_a?(Module)
      return
    end

    if mod.singleton_class?
      mod.include(SingletonMethodHooks)
    else
      mod.extend(MethodHooks)
    end
    mod.extend(SingletonMethodHooks)
  end

  # use this directly if you don't want/need to box up the method into an object to pass to method_to_key.
  private_class_method def self.method_owner_and_name_to_key(owner, name)
    "#{owner.object_id}##{name}"
  end

  private_class_method def self.method_to_key(method)
    method_owner_and_name_to_key(method.owner, method.name)
  end

  private_class_method def self.key_to_method(key)
    id, name = key.split("#")
    obj = ObjectSpace._id2ref(id.to_i)
    obj.instance_method(name)
  end
end

# This has to be here, and can't be nested inside `T::Private::Methods`,
# because the value of `self` depends on lexical (nesting) scope, and we
# specifically need a reference to the file-level self, i.e. `main:Object`
T::Private::Methods::TOP_SELF = self
