# frozen_string_literal: true
# typed: false

# Cut down version of Chalk::Tools::ClassUtils with only :replace_method functionality.
# Extracted to a separate namespace so the type system can be used standalone.
module T::Private::ClassUtils
  class ReplacedMethod
    def initialize(mod, old_method, new_method, overwritten, visibility)
      if old_method.name != new_method.name
        raise "Method names must match. old=#{old_method.name} new=#{new_method.name}"
      end
      @mod = mod
      @old_method = old_method
      @new_method = new_method
      @overwritten = overwritten
      @name = old_method.name
      @visibility = visibility
      @restored = false
    end

    def restore
      # The check below would also catch this, but this makes the failure mode much clearer
      if @restored
        raise "Method '#{@name}' on '#{@mod}' was already restored"
      end

      if @mod.instance_method(@name) != @new_method
        raise "Trying to restore #{@mod}##{@name} but the method has changed since the call to replace_method"
      end

      @restored = true

      if @overwritten
        # The original method was overwritten. Overwrite again to restore it.
        T::Configuration.without_ruby_warnings do
          @mod.send(:define_method, @old_method.name, @old_method)
        end
      else
        # The original method was in an ancestor. Restore it by removing the overriding method.
        @mod.send(:remove_method, @old_method.name)
      end

      # Restore the visibility. Note that we need to do this even when we call remove_method
      # above, because the module may have set custom visibility for a method it inherited.
      @mod.send(@visibility, @old_method.name)

      nil
    end

    def bind(obj)
      @old_method.bind(obj)
    end

    def to_s
      @old_method.to_s
    end
  end

  # `name` must be an instance method (for class methods, pass in mod.singleton_class)
  private_class_method def self.visibility_method_name(mod, name)
    if mod.public_method_defined?(name)
      :public
    elsif mod.protected_method_defined?(name)
      :protected
    elsif mod.private_method_defined?(name)
      :private
    else
      mod.method(name) # Raises
    end
  end

  def self.def_with_visibility(mod, name, visibility, method=nil, &block)
    mod.module_exec do
      # Start a visibility (public/protected/private) region, so that
      # all of the method redefinitions happen with the right visibility
      # from the beginning. This ensures that any other code that is
      # triggered by `method_added`, sees the redefined method with the
      # right visibility.
      send(visibility)

      if method
        define_method(name, method)
      else
        define_method(name, &block)
      end

      if block && block.arity < 0 && respond_to?(:ruby2_keywords, true)
        ruby2_keywords(name)
      end
    end
  end

  # Replaces a method, either by overwriting it (if it is defined directly on `mod`) or by
  # overriding it (if it is defined by one of mod's ancestors).  If `original_only` is
  # false, returns a ReplacedMethod instance on which you can call `bind(...).call(...)`
  # to call the original method, or `restore` to restore the original method (by
  # overwriting or removing the override).
  #
  # If `original_only` is true, return the `UnboundMethod` representing the original method.
  def self.replace_method(mod, name, original_only=false, &blk)
    original_method = mod.instance_method(name)
    original_visibility = visibility_method_name(mod, name)
    original_owner = original_method.owner

    mod.ancestors.each do |ancestor|
      break if ancestor == mod
      if ancestor == original_owner
        # If we get here, that means the method we're trying to replace exists on a *prepended*
        # mixin, which means in order to supersede it, we'd need to create a method on a new
        # module that we'd prepend before `ancestor`. The problem with that approach is there'd
        # be no way to remove that new module after prepending it, so we'd be left with these
        # empty anonymous modules in the ancestor chain after calling `restore`.
        #
        # That's not necessarily a deal breaker, but for now, we're keeping it as unsupported.
        raise "You're trying to replace `#{name}` on `#{mod}`, but that method exists in a " \
              "prepended module (#{ancestor}), which we don't currently support."
      end
    end

    overwritten = original_owner == mod
    T::Configuration.without_ruby_warnings do
      T::Private::DeclState.current.without_on_method_added do
        def_with_visibility(mod, name, original_visibility, &blk)
      end
    end

    if original_only
      original_method
    else
      new_method = mod.instance_method(name)
      ReplacedMethod.new(mod, original_method, new_method, overwritten, original_visibility)
    end
  end
end
