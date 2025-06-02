# frozen_string_literal: true

module RBS
  module Test
    class Tester
      attr_reader :env
      attr_reader :targets
      attr_reader :instance_testers
      attr_reader :singleton_testers

      def initialize(env:)
        @env = env
        @targets = []
        @instance_testers = {}
        @singleton_testers = {}
      end

      def factory
        @factory ||= Factory.new
      end

      def builder
        @builder ||= DefinitionBuilder.new(env: env)
      end

      def skip_method?(type_name, method)
        if method.implemented_in == type_name
          if method.annotations.any? {|a| a.string == "rbs:test:skip" }
            :skip
          else
            false
          end
        else
          if method.annotations.any? {|a| a.string == "rbs:test:target" }
            false
          else
            :implemented_in
          end
        end
      end

      def install!(klass, sample_size:, unchecked_classes:)
        RBS.logger.info { "Installing runtime type checker in #{klass}..." }

        type_name = factory.type_name(klass.name).absolute!

        builder.build_instance(type_name).tap do |definition|
          instance_key = new_key(type_name, "InstanceChecker")
          tester, set = instance_testers[klass] ||= [
            MethodCallTester.new(klass, builder, definition, kind: :instance, sample_size: sample_size, unchecked_classes: unchecked_classes),
            Set[]
          ]
          Observer.register(instance_key, tester)

          definition.methods.each do |name, method|
            if reason = skip_method?(type_name, method)
              unless reason == :implemented_in
                RBS.logger.info { "Skipping ##{name} because of `#{reason}`..." }
              end
            else
              if !set.include?(name) && (
                  name == :initialize ||
                  klass.instance_methods(false).include?(name) ||
                  klass.private_instance_methods(false).include?(name))
                RBS.logger.info { "Setting up method hook in ##{name}..." }
                Hook.hook_instance_method klass, name, key: instance_key
                set << name
              end
            end
          end
        end

        builder.build_singleton(type_name).tap do |definition|
          singleton_key = new_key(type_name, "SingletonChecker")
          tester, set = singleton_testers[klass] ||= [
            MethodCallTester.new(klass.singleton_class, builder, definition, kind: :singleton, sample_size: sample_size, unchecked_classes: unchecked_classes),
            Set[]
          ]
          Observer.register(singleton_key, tester)

          definition.methods.each do |name, method|
            if reason = skip_method?(type_name, method)
              unless reason == :implemented_in
                RBS.logger.info { "Skipping .#{name} because of `#{reason}`..." }
              end
            else
              if klass.methods(false).include?(name) && !set.include?(name)
                RBS.logger.info { "Setting up method hook in .#{name}..." }
                Hook.hook_singleton_method klass, name, key: singleton_key
                set << name
              end
            end
          end
        end

        targets << klass
      end

      def new_key(type_name, prefix)
        "#{prefix}__#{type_name}__#{SecureRandom.hex(10)}"
      end

      class TypeError < Exception
        attr_reader :errors

        def initialize(errors)
          @errors = errors

          super "TypeError: #{errors.map {|e| Errors.to_string(e) }.join(", ")}"
        end
      end

      class MethodCallTester
        attr_reader :self_class
        attr_reader :definition
        attr_reader :builder
        attr_reader :kind
        attr_reader :sample_size
        attr_reader :unchecked_classes

        def initialize(self_class, builder, definition, kind:, sample_size:, unchecked_classes:)
          @self_class = self_class
          @definition = definition
          @builder = builder
          @kind = kind
          @sample_size = sample_size
          @unchecked_classes = unchecked_classes
        end

        def env
          builder.env
        end

        def check
          @check ||= TypeCheck.new(self_class: self_class, builder: builder, sample_size: sample_size, unchecked_classes: unchecked_classes)
        end

        def format_method_name(name)
          case kind
          when :instance
            "##{name}"
          when :singleton
            ".#{name}"
          end
        end

        def call(receiver, trace)
          method_name = trace.method_name
          method = definition.methods[method_name]
          if method
            RBS.logger.debug { "Type checking `#{self_class}#{format_method_name(method_name)}`..."}
            errors = check.overloaded_call(method, format_method_name(method_name), trace, errors: [])

            if errors.empty?
              RBS.logger.debug { "No type error detected 👏" }
            else
              RBS.logger.debug { "Detected type error 🚨" }
              raise TypeError.new(errors)
            end
          else
            RBS.logger.error { "Type checking `#{self_class}#{method_name}` call but no method found in definition" }
          end
        end
      end
    end
  end
end
