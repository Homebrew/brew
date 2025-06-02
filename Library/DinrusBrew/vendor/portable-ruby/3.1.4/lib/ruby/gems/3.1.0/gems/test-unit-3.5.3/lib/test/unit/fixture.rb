module Test
  module Unit
    module Fixture
      class << self
        def included(base)
          base.extend(ClassMethods)

          [:setup, :cleanup, :teardown].each do |type|
            observer = lambda do |test_case, _, _, value, callback|
              if value.nil?
                test_case.fixture[type].unregister(callback)
              else
                test_case.fixture[type].register(callback, value)
              end
            end
            base.register_attribute_observer(type, &observer)
          end
        end
      end

      class Fixture
        attr_reader :setup
        attr_reader :cleanup
        attr_reader :teardown
        def initialize(test_case)
          @test_case = test_case
          @setup = HookPoint.new(@test_case, :setup, :after => :append)
          @cleanup = HookPoint.new(@test_case, :cleanup, :before => :prepend)
          @teardown = HookPoint.new(@test_case, :teardown, :before => :prepend)
          @cached_before_callbacks = {}
          @cached_after_callbacks = {}
        end

        def [](type)
          case type
          when :setup
            @setup
          when :cleanup
            @cleanup
          when :teardown
            @teardown
          end
        end

        def before_callbacks(type)
          @cached_before_callbacks[type] ||= collect_before_callbacks(type)
        end

        def after_callbacks(type)
          @cached_after_callbacks[type] ||= collect_after_callbacks(type)
        end

        private
        def target_test_cases
          @cached_target_test_cases ||= collect_target_test_cases
        end

        def collect_before_callbacks(type)
          prepend_callbacks = []
          append_callbacks = []
          target_test_cases.each do |ancestor|
            prepend_callbacks << ancestor.fixture[type].before_prepend_callbacks
            append_callbacks << ancestor.fixture[type].before_append_callbacks
          end

          merge_callbacks(prepend_callbacks, append_callbacks)
        end

        def collect_after_callbacks(type)
          prepend_callbacks = []
          append_callbacks = []
          target_test_cases.each do |ancestor|
            prepend_callbacks << ancestor.fixture[type].after_prepend_callbacks
            append_callbacks << ancestor.fixture[type].after_append_callbacks
          end

          merge_callbacks(prepend_callbacks, append_callbacks)
        end

        def collect_target_test_cases
          ancestors = @test_case.ancestors
          base_index = ancestors.index(::Test::Unit::Fixture)
          interested_ancestors = ancestors[0, base_index].find_all do |ancestor|
            ancestor.is_a?(Class)
          end
          interested_ancestors.reverse
        end

        def merge_callbacks(prepend_callbacks, append_callbacks)
          all_callbacks = []
          prepend_callbacks.reverse_each do |callbacks|
            all_callbacks.concat(callbacks)
          end
          append_callbacks.each do |callbacks|
            all_callbacks.concat(callbacks)
          end
          all_callbacks
        end
      end

      class HookPoint
        def initialize(test_case, type, default_options)
          @test_case = test_case
          @type = type
          @default_options = default_options
          @callbacks = {}
          @before_prepend_callbacks = []
          @before_append_callbacks = []
          @after_prepend_callbacks = []
          @after_append_callbacks = []
          @unregistered_callbacks = []
        end

        def register(method_name_or_callback, options=nil)
          options ||= {}
          unless valid_register_options?(options)
            message = "must be {:before => :prepend}, " +
              "{:before => :append}, {:after => :prepend} or " +
              "{:after => :append}: #{options.inspect}"
            raise ArgumentError, message
          end

          if options.empty?
            options = @default_options
          end
          before_how = options[:before]
          after_how = options[:after]
          if method_name_or_callback.respond_to?(:call)
            callback = method_name_or_callback
            method_name = callback_method_name(callback)
            @test_case.attribute(:source_location,
                                 callback.source_location,
                                 method_name)
            # For Ruby 2.6 or earlier. callback may be GC-ed. If
            # callback is GC-ed, callback_method_name may be
            # duplicated because callback_method_name uses callback.object_id.
            # See also: https://github.com/test-unit/test-unit/issues/179
            @callbacks[callback] = true
            @test_case.__send__(:define_method, method_name, &callback)
          else
            method_name = method_name_or_callback
          end
          add_callback(method_name, before_how, after_how)
        end

        def unregister(method_name_or_callback)
          if method_name_or_callback.respond_to?(:call)
            callback = method_name_or_callback
            method_name = callback_method_name(callback)
          else
            method_name = method_name_or_callback
          end
          @unregistered_callbacks << method_name
        end

        def before_prepend_callbacks
          @before_prepend_callbacks - @unregistered_callbacks
        end

        def before_append_callbacks
          @before_append_callbacks - @unregistered_callbacks
        end

        def after_prepend_callbacks
          @after_prepend_callbacks - @unregistered_callbacks
        end

        def after_append_callbacks
          @after_append_callbacks - @unregistered_callbacks
        end

        private
        def valid_register_options?(options)
          return true if options.empty?
          return false if options.size > 1

          key = options.keys.first
          [:before, :after].include?(key) and
            [:prepend, :append].include?(options[key])
        end

        def callback_method_name(callback)
          "#{@type}_#{callback.object_id}"
        end

        def add_callback(method_name_or_callback, before_how, after_how)
          case before_how
          when :prepend
            @before_prepend_callbacks =
              [method_name_or_callback] | @before_prepend_callbacks
          when :append
            @before_append_callbacks |= [method_name_or_callback]
          else
            case after_how
            when :prepend
              @after_prepend_callbacks =
                [method_name_or_callback] | @after_prepend_callbacks
            when :append
              @after_append_callbacks |= [method_name_or_callback]
            end
          end
        end
      end

      module ClassMethods
        def fixture
          @fixture ||= Fixture.new(self)
        end

        def setup(*method_names, &callback)
          register_fixture(:setup, *method_names, &callback)
        end

        def unregister_setup(*method_names_or_callbacks)
          unregister_fixture(:setup, *method_names_or_callbacks)
        end

        def cleanup(*method_names, &callback)
          register_fixture(:cleanup, *method_names, &callback)
        end

        def unregister_cleanup(*method_names_or_callbacks)
          unregister_fixture(:cleanup, *method_names_or_callbacks)
        end

        def teardown(*method_names, &callback)
          register_fixture(:teardown, *method_names, &callback)
        end

        def unregister_teardown(*method_names_or_callbacks)
          unregister_fixture(:teardown, *method_names_or_callbacks)
        end

        private
        def register_fixture(fixture, *method_names, &callback)
          options = {}
          options = method_names.pop if method_names.last.is_a?(Hash)
          callbacks = method_names
          callbacks << callback if callback
          attribute(fixture, options, *callbacks)
        end

        def unregister_fixture(fixture, *method_names_or_callbacks)
          attribute(fixture, nil, *method_names_or_callbacks)
        end
      end

      private
      def run_fixture(type, options={}, &block)
        fixtures = [
          self.class.fixture.before_callbacks(type),
          type,
          self.class.fixture.after_callbacks(type),
        ].flatten
        if block
          runner = create_fixtures_runner(fixtures, options, &block)
          runner.call
        else
          fixtures.each do |method_name|
            run_fixture_callback(method_name, options)
          end
        end
      end

      def create_fixtures_runner(fixtures, options, &block)
        if fixtures.empty?
          block
        else
          last_fixture = fixtures.pop
          create_fixtures_runner(fixtures, options) do
            block_is_called = false
            run_fixture_callback(last_fixture, options) do
              block_is_called = true
              block.call
            end
            block.call unless block_is_called
          end
        end
      end

      def run_fixture_callback(method_name, options, &block)
        return unless respond_to?(method_name, true)
        begin
          __send__(method_name, &block)
        rescue Exception
          raise unless options[:handle_exception]
          raise unless handle_exception($!)
        end
      end

      def run_setup(&block)
        run_fixture(:setup, &block)
      end

      def run_cleanup
        run_fixture(:cleanup)
      end

      def run_teardown
        run_fixture(:teardown, :handle_exception => true)
      end
    end
  end
end
