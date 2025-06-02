module Test
  module Unit
    module ExceptionHandler
      @@exception_handlers = []
      class << self
        def exception_handlers
          @@exception_handlers
        end

        def included(base)
          base.extend(ClassMethods)

          observer = Proc.new do |test_case, _, _, value, method_name|
            if value
              @@exception_handlers.unshift(method_name)
            else
              @@exception_handlers.delete(method_name)
            end
          end
          base.register_attribute_observer(:exception_handler, &observer)
        end
      end

      module ClassMethods
        def exception_handlers
          ExceptionHandler.exception_handlers
        end

        # @overload exception_handler(method_name)
        #   Add an exception handler method.
        #
        #   @param method_name [Symbol]
        #      The method name that handles exception raised in tests.
        #   @return [void]
        #
        # @overload exception_handler(&callback)
        #   Add an exception handler.
        #
        #   @yield [test, exception]
        #     Gives the test and the exception.
        #   @yieldparam test [Test::Unit::TestCase]
        #      The test where the exception is raised.
        #   @yieldparam exception [Exception]
        #      The exception that is raised in running the test.
        #   @yieldreturn [Boolean]
        #      Whether the handler handles the exception or not.
        #      The handler must return _true_ if the handler handles
        #      test exception, _false_ otherwise.
        #   @return [void]
        #
        # This is a public API for developers who extend test-unit.
        def exception_handler(*method_name_or_handlers, &block)
          if block_given?
            exception_handlers.unshift(block)
          else
            method_name_or_handlers.each do |method_name_or_handler|
              if method_name_or_handler.respond_to?(:call)
                handler = method_name_or_handler
                exception_handlers.unshift(handler)
              else
                method_name = method_name_or_handler
                attribute(:exception_handler, true, {}, method_name)
              end
            end
          end
        end

        def unregister_exception_handler(*method_name_or_handlers)
          method_name_or_handlers.each do |method_name_or_handler|
            if method_name_or_handler.respond_to?(:call)
              handler = method_name_or_handler
              exception_handlers.delete(handler)
            else
              method_name = method_name_or_handler
              attribute(:exception_handler, false, {}, method_name)
            end
          end
        end
      end
    end
  end
end
