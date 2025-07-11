# frozen_string_literal: true
# typed: false

module T::Props

  # Helper for generating methods that replace themselves with a specialized
  # version on first use. The main use case is when we want to generate a
  # method using the full set of props on a class; we can't do that during
  # prop definition because we have no way of knowing whether we are defining
  # the last prop.
  #
  # See go/M8yrvzX2 (Stripe-internal) for discussion of security considerations.
  # In outline, while `class_eval` is a bit scary, we believe that as long as
  # all inputs are defined in version control (and this is enforced by calling
  # `disable_lazy_evaluation!` appropriately), risk isn't significantly higher
  # than with build-time codegen.
  module HasLazilySpecializedMethods
    extend T::Sig

    class SourceEvaluationDisabled < RuntimeError
      def initialize
        super("Evaluation of lazily-defined methods is disabled")
      end
    end

    # Disable any future evaluation of lazily-defined methods.
    #
    # This is intended to be called after startup but before interacting with
    # the outside world, to limit attack surface for our `class_eval` use.
    #
    # Note it does _not_ prevent explicit calls to `eagerly_define_lazy_methods!`
    # from working.
    sig { void }
    def self.disable_lazy_evaluation!
      @lazy_evaluation_disabled ||= true
    end

    sig { returns(T::Boolean) }
    def self.lazy_evaluation_enabled?
      !defined?(@lazy_evaluation_disabled) || !@lazy_evaluation_disabled
    end

    module DecoratorMethods
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.proc.returns(String)]).checked(:never) }
      private def lazily_defined_methods
        @lazily_defined_methods ||= {}
      end

      sig { returns(T::Hash[Symbol, T.untyped]).checked(:never) }
      private def lazily_defined_vm_methods
        @lazily_defined_vm_methods ||= {}
      end

      sig { params(name: Symbol).void }
      private def eval_lazily_defined_method!(name)
        if !HasLazilySpecializedMethods.lazy_evaluation_enabled?
          raise SourceEvaluationDisabled.new
        end

        source = lazily_defined_methods.fetch(name).call

        cls = decorated_class
        T::Configuration.without_ruby_warnings do
          cls.class_eval(source.to_s)
        end
        cls.send(:private, name)
      end

      sig { params(name: Symbol).void }
      private def eval_lazily_defined_vm_method!(name)
        if !HasLazilySpecializedMethods.lazy_evaluation_enabled?
          raise SourceEvaluationDisabled.new
        end

        lazily_defined_vm_methods.fetch(name).call

        cls = decorated_class
        cls.send(:private, name)
      end

      sig { params(name: Symbol, blk: T.proc.returns(String)).void }
      private def enqueue_lazy_method_definition!(name, &blk)
        lazily_defined_methods[name] = blk

        cls = decorated_class
        if cls.method_defined?(name) || cls.private_method_defined?(name)
          # Ruby does not emit "method redefined" warnings for aliased methods
          # (more robust than undef_method that would create a small window in which the method doesn't exist)
          cls.send(:alias_method, name, name)
        end
        cls.send(:define_method, name) do |*args|
          self.class.decorator.send(:eval_lazily_defined_method!, name)
          send(name, *args)
        end
        if cls.respond_to?(:ruby2_keywords, true)
          cls.send(:ruby2_keywords, name)
        end
        cls.send(:private, name)
      end

      sig { params(name: Symbol, blk: T.untyped).void }
      private def enqueue_lazy_vm_method_definition!(name, &blk)
        lazily_defined_vm_methods[name] = blk

        cls = decorated_class
        cls.send(:define_method, name) do |*args|
          self.class.decorator.send(:eval_lazily_defined_vm_method!, name)
          send(name, *args)
        end
        if cls.respond_to?(:ruby2_keywords, true)
          cls.send(:ruby2_keywords, name)
        end
        cls.send(:private, name)
      end

      sig { void }
      def eagerly_define_lazy_methods!
        return if lazily_defined_methods.empty?

        # rubocop:disable Style/StringConcatenation
        source = "# frozen_string_literal: true\n" + lazily_defined_methods.values.map(&:call).map(&:to_s).join("\n\n")
        # rubocop:enable Style/StringConcatenation

        cls = decorated_class
        cls.class_eval(source)
        lazily_defined_methods.each_key { |name| cls.send(:private, name) }
        lazily_defined_methods.clear
      end

      sig { void }
      def eagerly_define_lazy_vm_methods!
        return if lazily_defined_vm_methods.empty?

        lazily_defined_vm_methods.values.map(&:call)

        cls = decorated_class
        lazily_defined_vm_methods.each_key { |name| cls.send(:private, name) }
        lazily_defined_vm_methods.clear
      end
    end
  end
end
