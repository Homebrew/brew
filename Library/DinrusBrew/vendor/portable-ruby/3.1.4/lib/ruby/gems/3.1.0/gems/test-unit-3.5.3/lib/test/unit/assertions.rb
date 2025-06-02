# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
#             Copyright (c) 2009-2013 Kouhei Sutou. All rights reserved.
# License:: Ruby license.

require 'test/unit/assertion-failed-error'
require 'test/unit/util/backtracefilter'
require 'test/unit/util/memory-usage'
require 'test/unit/util/method-owner-finder'
require 'test/unit/diff'

begin
  require 'power_assert'
rescue LoadError, SyntaxError
end

module Test
  module Unit

    ##
    # Test::Unit::Assertions contains the standard Test::Unit assertions.
    # Assertions is included in Test::Unit::TestCase.
    #
    # To include it in your own code and use its functionality, you simply
    # need to rescue Test::Unit::AssertionFailedError. Additionally you may
    # override add_assertion to get notified whenever an assertion is made.
    #
    # Notes:
    #
    # * The message to each assertion, if given, will be propagated with the
    #   failure.
    # * It is easy to add your own assertions based on assert_block().
    #
    # @example Example Custom Assertion
    #
    #   def deny(boolean, message=nil)
    #     message = build_message(message, '<?> is not false or nil.', boolean)
    #     assert_block(message) do
    #       not boolean
    #     end
    #   end

    module Assertions

      ##
      # The assertion upon which all other assertions are based. Passes if the
      # block yields not false nor nil.
      #
      # @example
      #   assert_block "Couldn't do the thing" do
      #     do_the_thing
      #   end
      def assert_block(message="assert_block failed.")
        _wrap_assertion do
          if (! yield)
            options = {}
            if message.respond_to?(:user_message)
              options[:user_message] = message.user_message
            end
            raise AssertionFailedError.new(message.to_s, options)
          end
        end
      end

      # @private
      NOT_SPECIFIED = Object.new

      # @overload assert(object, message=nil)
      #
      #   Asserts that `object` is not false nor nil.
      #
      #   Normally, you don't need to use this assertion. Use more
      #   specific assertions such as #assert_equal and
      #   #assert_include.
      #
      #   @example Pass patterns
      #     assert(true)               # => pass
      #     assert([1, 2].include?(1)) # => pass
      #
      #   @example Failure patterns
      #     assert(nil)                # => failure
      #     assert(false)              # => failure
      #     assert([1, 2].include?(5)) # => failure
      #
      #   @param [Object] object The check target.
      #   @param [String] message The additional user message. It is
      #     showed when the assertion is failed.
      #   @return [void]
      #
      # @overload assert(message=nil) {}
      #
      #   Asserts that the givens block returns not false nor nil.
      #
      #   This style uses Power Assert. It means that you can see each
      #   object values in method chains on failure. See the following
      #   example about Power Assert.
      #
      #   @example Power Assert
      #     coins = [1, 5, 50]
      #     target_coin = 10
      #     assert do
      #       coins.include?(target_coin)
      #     end
      #     # =>
      #     #  coins.include?(target_coin)
      #     #  |     |        |
      #     #  |     |        10
      #     #  |     false
      #     #  [1, 5, 50]
      #
      #   We recommend you to use Power Assert for predicate method
      #   checks rather than existing assertions such as
      #   #assert_include and #assert_predicate. Power Assert shows
      #   useful message for debugging.
      #
      #   We don't recommend you use Power Assert for equality
      #   check. You should use #assert_equal for the case. Because
      #   #assert_equal shows more useful message for debugging.
      #
      #   @example Pass patterns
      #     assert {true}               # => pass
      #     assert {[1, 2].include?(1)} # => pass
      #
      #   @example Failure patterns
      #     assert {nil}                # => failure
      #     assert {false}              # => failure
      #     assert {[1, 2].include?(5)} # => failure
      #
      #   @param [String] message The additional user message. It is
      #     showed when the assertion is failed.
      #   @yield [] Given no parameters to the block.
      #   @yieldreturn [Object] The checked object.
      #   @return [void]
      def assert(object=NOT_SPECIFIED, message=nil, &block)
        _wrap_assertion do
          have_object = !NOT_SPECIFIED.equal?(object)
          if block
            message = object if have_object
            if defined?(PowerAssert)
              PowerAssert.start(block, :assertion_method => __callee__) do |pa|
                pa_message = AssertionMessage.delayed_literal(&pa.message_proc)
                assertion_message = build_message(message, "?", pa_message)
                assert_block(assertion_message) do
                  pa.yield
                end
              end
            else
              assert(yield, message)
            end
          else
            unless have_object
              raise ArgumentError, "wrong number of arguments (0 for 1..2)"
            end
            assertion_message = nil
            case message
            when nil, String, Proc
            when AssertionMessage
              assertion_message = message
            else
              error_message = "assertion message must be String, Proc or "
              error_message += "#{AssertionMessage}: "
              error_message += "<#{message.inspect}>(<#{message.class}>)"
              raise ArgumentError, error_message, filter_backtrace(caller)
            end
            assertion_message ||= build_message(message,
                                                "<?> is not true.",
                                                object)
            assert_block(assertion_message) do
              object
            end
          end
        end
      end

      # Asserts that `object` is false or nil.
      #
      # @note Just for minitest compatibility. :<
      #
      # @param [Object] object The object to be asserted.
      # @return [void]
      #
      # @example Pass patterns
      #   refute(false)    # => pass
      #   refute(nil)      # => pass
      #
      # @example Failure patterns
      #   refute(true)     # => failure
      #   refute("string") # => failure
      #
      # @since 2.5.3
      def refute(object, message=nil)
        _wrap_assertion do
          assertion_message = nil
          case message
          when nil, String, Proc
          when AssertionMessage
            assertion_message = message
          else
            error_message = "assertion message must be String, Proc or "
            error_message += "#{AssertionMessage}: "
            error_message += "<#{message.inspect}>(<#{message.class}>)"
            raise ArgumentError, error_message, filter_backtrace(caller)
          end
          assert_block("refute should not be called with a block.") do
            !block_given?
          end
          assertion_message ||= build_message(message,
                                              "<?> is neither nil or false.",
                                              object)
          assert_block(assertion_message) do
            not object
          end
        end
      end

      ##
      # Passes if `expected` == `actual`.
      #
      # Note that the ordering of arguments is important, since a helpful
      # error message is generated when this one fails that tells you the
      # values of expected and actual.
      #
      # @example
      #   assert_equal 'MY STRING', 'my string'.upcase
      def assert_equal(expected, actual, message=nil)
        diff = AssertionMessage.delayed_diff(expected, actual)
        if expected.respond_to?(:encoding) and
            actual.respond_to?(:encoding) and
            expected.encoding != actual.encoding
          format = <<EOT
<?>(?) expected but was
<?>(?).?
EOT
          full_message = build_message(message, format,
                                       expected, expected.encoding.name,
                                       actual, actual.encoding.name,
                                       diff)
        else
          full_message = build_message(message, <<EOT, expected, actual, diff)
<?> expected but was
<?>.?
EOT
        end
        begin
          assert_block(full_message) { expected == actual }
        rescue AssertionFailedError => failure
          _set_failed_information(failure, expected, actual)
          raise failure # For JRuby. :<
        end
      end

      ##
      # Passes if the block raises one of the expected
      # exceptions. When an expected exception is an Exception
      # object, passes if expected_exception == actual_exception.
      #
      # @example
      #   assert_raise(RuntimeError, LoadError) do
      #     raise 'Boom!!!'
      #   end # -> pass
      #
      #   assert_raise do
      #     raise Exception, 'Any exception should be raised!!!'
      #   end # -> pass
      #
      #   assert_raise(RuntimeError.new("XXX")) {raise "XXX"} # -> pass
      #   assert_raise(MyError.new("XXX"))      {raise "XXX"} # -> fail
      #   assert_raise(RuntimeError.new("ZZZ")) {raise "XXX"} # -> fail
      def assert_raise(*args, &block)
        assert_expected_exception = Proc.new do |*_args|
          message, assert_exception_helper, actual_exception = _args
          expected = assert_exception_helper.expected_exceptions
          diff = AssertionMessage.delayed_diff(expected, actual_exception)
          full_message = build_message(message,
                                       "<?> exception expected but was\n<?>.?",
                                       expected, actual_exception, diff)
          begin
            assert_block(full_message) do
              expected == [] or
                assert_exception_helper.expected?(actual_exception)
            end
          rescue AssertionFailedError => failure
            _set_failed_information(failure, expected, actual_exception)
            raise failure # For JRuby. :<
          end
        end
        _assert_raise(assert_expected_exception, *args, &block)
      end

      # Just for minitest compatibility. :<
      alias_method :assert_raises, :assert_raise

      # Passes if the block raises `expected_exception` with
      # `expected_message`. `expected_message` can be a `String` or
      # `Regexp`.
      #
      # @example Pass pattern: String
      #   assert_raise_with_message(RuntimeError, "Boom!!!") do
      #     raise "Boom!!!"
      #   end # -> pass
      #
      # @example Pass pattern: Regexp
      #   assert_raise_with_message(RuntimeError, /!!!/) do
      #     raise "Boom!!!"
      #   end # -> pass
      #
      # @example Failure pattern: Exception class isn't matched
      #   assert_raise_with_message(RuntimeError, "Boom!!!") do
      #     raise ArgumentError, "Boom!!!"
      #   end # -> failure
      #
      # @example Failure pattern: Exception message isn't matched
      #   assert_raise_with_message(RuntimeError, "Boom!!!") do
      #     raise "Hello"
      #   end # -> failure
      #
      # @since 3.4.3
      def assert_raise_with_message(expected_exception_class,
                                    expected_message,
                                    message=nil,
                                    &block)
        assert_expected_exception = Proc.new do |*_args|
          _message, assert_exception_helper, actual_exception = _args
          diff = AssertionMessage.delayed_diff([
                                                 expected_exception_class,
                                                 expected_message,
                                               ],
                                               [
                                                 actual_exception.class,
                                                 actual_exception.message,
                                               ])
          full_message = build_message(message,
                                       "<?>(<?>) exception expected but was\n" +
                                       "<?>(<?>).?",
                                       expected_exception_class,
                                       expected_message,
                                       actual_exception.class,
                                       actual_exception.message,
                                       diff)
          begin
            assert_block(full_message) do
              assert_exception_helper.expected?(actual_exception) and
                expected_message === actual_exception.message
            end
          rescue AssertionFailedError => failure
            _set_failed_information(failure,
                                    expected_exception_class,
                                    actual_exception)
            raise failure # For JRuby. :<
          end
          actual_exception
        end
        args = [expected_exception_class]
        args << message if message
        _assert_raise(assert_expected_exception, *args, &block)
      end

      ##
      # Passes if the block raises one of the given
      # exceptions or sub exceptions of the given exceptions.
      #
      # @example
      #   assert_raise_kind_of(SystemCallError) do
      #     raise Errno::EACCES
      #   end
      def assert_raise_kind_of(*args, &block)
        assert_expected_exception = Proc.new do |*_args|
          message, assert_exception_helper, actual_exception = _args
          expected = assert_exception_helper.expected_exceptions
          full_message = build_message(message,
                                       "<?> family exception expected " +
                                       "but was\n<?>.",
                                       expected, actual_exception)
          assert_block(full_message) do
            assert_exception_helper.expected?(actual_exception, :kind_of?)
          end
        end
        _assert_raise(assert_expected_exception, *args, &block)
      end


      ##
      # Passes if `object`.instance_of?(`klass`). When `klass` is
      # an array of classes, it passes if any class
      # satisfies +object.instance_of?(class).
      #
      # @example
      #   assert_instance_of(String, 'foo')            # -> pass
      #   assert_instance_of([Fixnum, NilClass], 100)  # -> pass
      #   assert_instance_of([Numeric, NilClass], 100) # -> fail
      def assert_instance_of(klass, object, message=nil)
        _wrap_assertion do
          if klass.is_a?(Array)
            klasses = klass
          else
            klasses = [klass]
          end
          assert_block("The first parameter to assert_instance_of should be " +
                       "a Class or an Array of Class.") do
            klasses.all? {|k| k.is_a?(Class)}
          end
          klass_message = AssertionMessage.maybe_container(klass) do |value|
            "<#{value}>"
          end
          full_message = build_message(message, <<EOT, object, klass_message, object.class)
<?> was expected to be instance_of\\?
? but was
<?>.
EOT
          assert_block(full_message) do
            klasses.any? {|k| object.instance_of?(k)}
          end
        end
      end

      ##
      # Passes if `object`.instance_of?(`klass`) does not hold.
      # When `klass` is an array of classes, it passes if no class
      # satisfies +object.instance_of?(class).
      #
      # @example
      #   assert_not_instance_of(String, 100)                # -> pass
      #   assert_not_instance_of([Fixnum, NilClass], '100')  # -> pass
      #   assert_not_instance_of([Numeric, NilClass], 100)   # -> fail
      #
      # @since 3.0.0
      def assert_not_instance_of(klass, object, message=nil)
        _wrap_assertion do
          if klass.is_a?(Array)
            klasses = klass
          else
            klasses = [klass]
          end
          assert_block("The first parameter to assert_not_instance_of should be " +
                       "a Class or an Array of Class.") do
            klasses.all? {|k| k.is_a?(Class)}
          end
          klass_message = AssertionMessage.maybe_container(klass) do |value|
            "<#{value}>"
          end
          full_message = build_message(message,
                                       "<?> was expected to not be instance_of\\?\n" +
                                       "? but was.",
                                       object,
                                       klass_message)
          assert_block(full_message) do
            klasses.none? {|k| object.instance_of?(k)}
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_instance_of, :assert_not_instance_of

      ##
      # Passes if `object`.nil?.
      #
      # @example
      #   assert_nil [1, 2].uniq!
      def assert_nil(object, message=nil)
        full_message = build_message(message, <<EOT, object)
<?> was expected to be nil.
EOT
        assert_block(full_message) { object.nil? }
      end

      ##
      # Passes if `object`.kind_of?(`klass`). When `klass` is
      # an array of classes or modules, it passes if any
      # class or module satisfies +object.kind_of?(class_or_module).
      #
      # @example
      #   assert_kind_of(Object, 'foo')                # -> pass
      #   assert_kind_of([Fixnum, NilClass], 100)      # -> pass
      #   assert_kind_of([Fixnum, NilClass], "string") # -> fail
      def assert_kind_of(klass, object, message=nil)
        _wrap_assertion do
          if klass.is_a?(Array)
            klasses = klass
          else
            klasses = [klass]
          end
          assert_block("The first parameter to assert_kind_of should be " +
                       "a kind_of Module or an Array of a kind_of Module.") do
            klasses.all? {|k| k.kind_of?(Module)}
          end
          klass_message = AssertionMessage.maybe_container(klass) do |value|
            "<#{value}>"
          end
          full_message = build_message(message,
                                       "<?> was expected to be kind_of\\?\n" +
                                       "? but was\n" +
                                       "<?>.",
                                       object,
                                       klass_message,
                                       object.class)
          assert_block(full_message) do
            klasses.any? {|k| object.kind_of?(k)}
          end
        end
      end

      ##
      # Passes if `object`.kind_of?(`klass`) does not hold.
      # When `klass` is an array of classes or modules, it passes only if all
      # classes (and modules) do not satisfy +object.kind_of?(class_or_module).
      #
      # @example
      #   assert_not_kind_of(Fixnum, 'foo')           # -> pass
      #   assert_not_kind_of([Fixnum, NilClass], '0') # -> pass
      #   assert_not_kind_of([Fixnum, NilClass], 100) # -> fail
      #
      # @since 3.0.0
      def assert_not_kind_of(klass, object, message=nil)
        _wrap_assertion do
          if klass.is_a?(Array)
            klasses = klass
          else
            klasses = [klass]
          end
          assert_block("The first parameter to assert_not_kind_of should be " +
                       "a kind_of Module or an Array of a kind_of Module.") do
            klasses.all? {|k| k.kind_of?(Module)}
          end
          klass_message = AssertionMessage.maybe_container(klass) do |value|
            "<#{value}>"
          end
          full_message = build_message(message,
                                       "<?> was expected to not be kind_of\\?\n" +
                                       "? but was.",
                                       object,
                                       klass_message)
          assert_block(full_message) do
            klasses.none? {|k| object.kind_of?(k)}
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_kind_of, :assert_not_kind_of

      ##
      # Passes if `object` .respond_to? `method`
      #
      # @example
      #   assert_respond_to 'bugbear', :slice
      def assert_respond_to(object, method, message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "<?>.kind_of\\?(Symbol) or\n" +
                                       "<?>.respond_to\\?(:to_str) expected",
                                       method, method)
          assert_block(full_message) do
            method.kind_of?(Symbol) or method.respond_to?(:to_str)
          end
          full_message = build_message(message,
                                       "<?>.respond_to\\?(?) expected\n" +
                                       "(Class: <?>)",
                                       object, method, object.class)
          assert_block(full_message) {object.respond_to?(method)}
        end
      end

      ##
      # Passes if `object` does not .respond_to? `method`.
      #
      # @example
      #   assert_not_respond_to('bugbear', :nonexistence) # -> pass
      #   assert_not_respond_to('bugbear', :size)         # -> fail
      def assert_not_respond_to(object, method, message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "<?>.kind_of\\?(Symbol) or\n" +
                                       "<?>.respond_to\\?(:to_str) expected",
                                       method, method)
          assert_block(full_message) do
            method.kind_of?(Symbol) or method.respond_to?(:to_str)
          end
          full_message = build_message(message,
                                       "!<?>.respond_to\\?(?) expected\n" +
                                       "(Class: <?>)",
                                       object, method, object.class)
          assert_block(full_message) {!object.respond_to?(method)}
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_respond_to, :assert_not_respond_to

      ##
      # Passes if `pattern` =~ `string`.
      #
      # @example
      #   assert_match(/\d+/, 'five, 6, seven')
      def assert_match(pattern, string, message=nil)
        _wrap_assertion do
          pattern = Regexp.new(Regexp.escape(pattern)) if pattern.is_a?(String)
          full_message = build_message(message,
                                       "<?> was expected to be =~\n<?>.",
                                       pattern, string)
          assert_block(full_message) { pattern =~ string }
        end
      end

      ##
      # Passes if `actual` .equal? `expected` (i.e. they are the same
      # instance).
      #
      # @example
      #   o = Object.new
      #   assert_same o, o
      def assert_same(expected, actual, message=nil)
        full_message = build_message(message, <<EOT, expected, expected.__id__, actual, actual.__id__)
<?>
with id <?> was expected to be equal\\? to
<?>
with id <?>.
EOT
        assert_block(full_message) { actual.equal?(expected) }
      end

      ##
      # Compares the `object1` with `object2` using `operator`.
      #
      # Passes if object1.__send__(operator, object2) is not false nor nil.
      #
      # @example
      #   assert_operator 5, :>=, 4
      def assert_operator(object1, operator, object2, message=nil)
        _wrap_assertion do
          full_message = build_message(nil, "<?>\ngiven as the operator for #assert_operator must be a Symbol or #respond_to\\?(:to_str).", operator)
          assert_block(full_message){operator.kind_of?(Symbol) || operator.respond_to?(:to_str)}
          full_message = build_message(message, <<EOT, object1, AssertionMessage.literal(operator), object2)
<?> was expected to be
?
<?>.
EOT
          assert_block(full_message) { object1.__send__(operator, object2) }
        end
      end

      ##
      # Compares the `object1` with `object2` using `operator`.
      #
      # Passes if object1.__send__(operator, object2) is false or nil.
      #
      # @example
      #   assert_not_operator(5, :<, 4) # => pass
      #   assert_not_operator(5, :>, 4) # => fail
      #
      # @since 3.0.0
      def assert_not_operator(object1, operator, object2, message=nil)
        _wrap_assertion do
          full_message = build_message(nil, "<?>\ngiven as the operator for #assert_not_operator must be a Symbol or #respond_to\\?(:to_str).", operator)
          assert_block(full_message){operator.kind_of?(Symbol) || operator.respond_to?(:to_str)}
          full_message = build_message(message, <<EOT, object1, AssertionMessage.literal(operator), object2)
<?> was expected to not be
?
<?>.
EOT
          assert_block(full_message) { ! object1.__send__(operator, object2) }
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_operator, :assert_not_operator

      ##
      # Passes if block does not raise an exception.
      #
      # @example
      #   assert_nothing_raised do
      #     [1, 2].uniq
      #   end
      def assert_nothing_raised(*args)
        _wrap_assertion do
          if args.last.is_a?(String)
            message = args.pop
          else
            message = ""
          end

          assert_exception_helper = AssertExceptionHelper.new(self, args)
          begin
            yield
          rescue Exception => e
            if ((args.empty? && !e.instance_of?(AssertionFailedError)) ||
                assert_exception_helper.expected?(e))
              failure_message = build_message(message, "Exception raised:\n?", e)
              assert_block(failure_message) {false}
            else
              raise
            end
          end
        end
      end

      ##
      # Flunk always fails.
      #
      # @example
      #   flunk 'Not done testing yet.'
      def flunk(message="Flunked")
        assert_block(build_message(message)){false}
      end

      ##
      # Passes if ! `actual` .equal? `expected`
      #
      # @example
      #   assert_not_same Object.new, Object.new
      def assert_not_same(expected, actual, message=nil)
        full_message = build_message(message, <<EOT, expected, expected.__id__, actual, actual.__id__)
<?>
with id <?> was expected to not be equal\\? to
<?>
with id <?>.
EOT
        assert_block(full_message) { !actual.equal?(expected) }
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_same, :assert_not_same

      ##
      # Passes if `expected` != `actual`
      #
      # @example
      #   assert_not_equal 'some string', 5
      def assert_not_equal(expected, actual, message=nil)
        full_message = build_message(message,
                                     "<?> was expected to be != to\n<?>.",
                                     expected, actual)
        assert_block(full_message) { expected != actual }
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_equal, :assert_not_equal

      ##
      # Passes if ! `object` .nil?
      #
      # @example
      #   assert_not_nil '1 two 3'.sub!(/two/, '2')
      def assert_not_nil(object, message=nil)
        full_message = build_message(message,
                                     "<?> was expected to not be nil.",
                                     object)
        assert_block(full_message){!object.nil?}
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_nil, :assert_not_nil

      ##
      # Passes if `regexp` !~ `string`
      #
      # @example
      #   assert_not_match(/two/, 'one 2 three')   # -> pass
      #   assert_not_match(/three/, 'one 2 three') # -> fail
      def assert_not_match(pattern, string, message=nil)
        _wrap_assertion do
          pattern = Regexp.new(Regexp.escape(pattern)) if pattern.is_a?(String)
          full_message = build_message(message,
                                       "<?> was expected to not match\n<?>.",
                                       pattern, string)
          assert_block(full_message) { pattern !~ string }
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_match, :assert_not_match

      ##
      # @deprecated Use {#assert_not_match} instead.
      #
      # Passes if `regexp` !~ `string`
      #
      # @example
      #   assert_no_match(/two/, 'one 2 three')   # -> pass
      #   assert_no_match(/three/, 'one 2 three') # -> fail
      def assert_no_match(regexp, string, message="")
        _wrap_assertion do
          assert_instance_of(Regexp, regexp,
                             "The first argument to assert_no_match " +
                             "should be a Regexp.")
          assert_not_match(regexp, string, message)
        end
      end

      # @private
      class ThrowTagExtractor
        @@have_uncaught_throw_error = const_defined?(:UncaughtThrowError)

        UncaughtThrowPatterns = {
          NameError => /^uncaught throw `(.+)'$/,
          ArgumentError => /^uncaught throw (`.+'|.+)$/,
          ThreadError => /^uncaught throw `(.+)' in thread /,
        }

        def initialize(error)
          @error = error
        end

        def extract_tag
          tag = nil
          if @@have_uncaught_throw_error
            return nil unless @error.is_a?(UncaughtThrowError)
            tag = @error.tag
          else
            pattern = UncaughtThrowPatterns[@error.class]
            return nil if pattern.nil?
            return nil unless pattern =~ @error.message
            tag = $1
          end
          normalize_tag(tag)
        end

        private
        def normalize_tag(tag)
          case tag
          when /\A:/
            tag[1..-1].intern
          when /\A`(.+)'\z/
            $1.intern
          when String
            tag.intern
          else
            tag
          end
        end
      end

      ##
      # Passes if the block throws `expected_object`
      #
      # @example
      #   assert_throw(:done) do
      #     throw(:done)
      #   end
      def assert_throw(expected_object, message=nil, &proc)
        _wrap_assertion do
          begin
            catch([]) {}
          rescue TypeError
            assert_instance_of(Symbol, expected_object,
                               "assert_throws expects the symbol that should be thrown for its first argument")
          end
          assert_block("Should have passed a block to assert_throw.") do
            block_given?
          end
          caught = true
          begin
            catch(expected_object) do
              proc.call
              caught = false
            end
            full_message = build_message(message,
                                         "<?> should have been thrown.",
                                         expected_object)
            assert_block(full_message) {caught}
          rescue => error
            extractor = ThrowTagExtractor.new(error)
            tag = extractor.extract_tag
            raise if tag.nil?
            full_message = build_message(message,
                                         "<?> was expected to be thrown but\n" +
                                         "<?> was thrown.",
                                         expected_object, tag)
            flunk(full_message)
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :assert_throws, :assert_throw

      ##
      # Passes if block does not throw anything.
      #
      # @example
      #  assert_nothing_thrown do
      #    [1, 2].uniq
      #  end
      def assert_nothing_thrown(message=nil, &proc)
        _wrap_assertion do
          assert(block_given?, "Should have passed a block to assert_nothing_thrown")
          begin
            proc.call
          rescue => error
            extractor = ThrowTagExtractor.new(error)
            tag = extractor.extract_tag
            raise if tag.nil?
            full_message = build_message(message,
                                         "<?> was thrown when nothing was expected",
                                         tag)
            flunk(full_message)
          end
          assert(true, "Expected nothing to be thrown")
        end
      end

      ##
      # Passes if `expected_float` and `actual_float` are equal
      # within `delta` tolerance.
      #
      # @example
      #   assert_in_delta 0.05, (50000.0 / 10**6), 0.00001
      def assert_in_delta(expected_float, actual_float, delta=0.001, message="")
        _wrap_assertion do
          _assert_in_delta_validate_arguments(expected_float,
                                              actual_float,
                                              delta)
          full_message = _assert_in_delta_message(expected_float,
                                                  actual_float,
                                                  delta,
                                                  message)
          assert_block(full_message) do
            (expected_float.to_f - actual_float.to_f).abs <= delta.to_f
          end
        end
      end

      ##
      # Passes if `expected_float` and `actual_float` are
      # not equal within `delta` tolerance.
      #
      # @example
      #   assert_not_in_delta(0.05, (50000.0 / 10**6), 0.00002) # -> pass
      #   assert_not_in_delta(0.05, (50000.0 / 10**6), 0.00001) # -> fail
      def assert_not_in_delta(expected_float, actual_float, delta=0.001, message="")
        _wrap_assertion do
          _assert_in_delta_validate_arguments(expected_float,
                                              actual_float,
                                              delta)
          full_message = _assert_in_delta_message(expected_float,
                                                  actual_float,
                                                  delta,
                                                  message,
                                                  :negative_assertion => true)
          assert_block(full_message) do
            (expected_float.to_f - actual_float.to_f).abs > delta.to_f
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :refute_in_delta, :assert_not_in_delta

      private
      def _assert_in_delta_validate_arguments(expected_float,
                                              actual_float,
                                              delta)
        {
          expected_float => "first float",
          actual_float => "second float",
          delta => "delta"
        }.each do |float, name|
          assert_respond_to(float, :to_f,
                            "The arguments must respond to to_f; " +
                            "the #{name} did not")
        end
        delta = delta.to_f
        assert_operator(delta, :>=, 0.0, "The delta should not be negative")
      end

      def _assert_in_delta_message(expected_float, actual_float, delta,
                                   message, options={})
        if options[:negative_assertion]
          format = <<-EOT
<?> -/+ <?> was expected to not include
<?>.
EOT
        else
          format = <<-EOT
<?> -/+ <?> was expected to include
<?>.
EOT
        end
        arguments = [expected_float, delta, actual_float]
        normalized_expected = expected_float.to_f
        normalized_actual = actual_float.to_f
        normalized_delta = delta.to_f
        relation_format = nil
        relation_arguments = nil
        if normalized_actual < normalized_expected - normalized_delta
          relation_format = "<<?> < <?>-<?>[?] <= <?>+<?>[?]>"
          relation_arguments = [actual_float,
                                expected_float, delta,
                                normalized_expected - normalized_delta,
                                expected_float, delta,
                                normalized_expected + normalized_delta]
        elsif normalized_actual <= normalized_expected + normalized_delta
          relation_format = "<<?>-<?>[?] <= <?> <= <?>+<?>[?]>"
          relation_arguments = [expected_float, delta,
                                normalized_expected - normalized_delta,
                                actual_float,
                                expected_float, delta,
                                normalized_expected + normalized_delta]
        else
          relation_format = "<<?>-<?>[?] <= <?>+<?>[?] < <?>>"
          relation_arguments = [expected_float, delta,
                                normalized_expected - normalized_delta,
                                expected_float, delta,
                                normalized_expected + normalized_delta,
                                actual_float]
        end

        if relation_format
          format += <<-EOT

Relation:
#{relation_format}
EOT
          arguments.concat(relation_arguments)
        end

        build_message(message, format, *arguments)
      end

      public
      ##
      # Passes if `expected_float` and `actual_float` are equal
      # within `epsilon` relative error of `expected_float`.
      #
      # @example
      #   assert_in_epsilon(10000.0, 9900.0, 0.1) # -> pass
      #   assert_in_epsilon(10000.0, 9899.0, 0.1) # -> fail
      def assert_in_epsilon(expected_float, actual_float, epsilon=0.001,
                            message="")
        _wrap_assertion do
          _assert_in_epsilon_validate_arguments(expected_float,
                                                actual_float,
                                                epsilon)
          full_message = _assert_in_epsilon_message(expected_float,
                                                    actual_float,
                                                    epsilon,
                                                    message)
          assert_block(full_message) do
            normalized_expected_float = expected_float.to_f
            if normalized_expected_float.zero?
              delta = epsilon.to_f ** 2
            else
              delta = normalized_expected_float * epsilon.to_f
            end
            delta = delta.abs
            (normalized_expected_float - actual_float.to_f).abs <= delta
          end
        end
      end

      ##
      # Passes if `expected_float` and `actual_float` are
      # not equal within `epsilon` relative error of
      # `expected_float`.
      #
      # @example
      #   assert_not_in_epsilon(10000.0, 9900.0, 0.1) # -> fail
      #   assert_not_in_epsilon(10000.0, 9899.0, 0.1) # -> pass
      def assert_not_in_epsilon(expected_float, actual_float, epsilon=0.001,
                                message="")
        _wrap_assertion do
          _assert_in_epsilon_validate_arguments(expected_float,
                                                actual_float,
                                                epsilon)
          full_message = _assert_in_epsilon_message(expected_float,
                                                    actual_float,
                                                    epsilon,
                                                    message,
                                                    :negative_assertion => true)
          assert_block(full_message) do
            normalized_expected_float = expected_float.to_f
            delta = normalized_expected_float * epsilon.to_f
            (normalized_expected_float - actual_float.to_f).abs > delta
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_in_epsilon, :assert_not_in_epsilon

      private
      def _assert_in_epsilon_validate_arguments(expected_float,
                                                actual_float,
                                                epsilon)
        {
          expected_float => "first float",
          actual_float => "second float",
          epsilon => "epsilon"
        }.each do |float, name|
          assert_respond_to(float, :to_f,
                            "The arguments must respond to to_f; " +
                            "the #{name} did not")
        end
        epsilon = epsilon.to_f
        assert_operator(epsilon, :>=, 0.0, "The epsilon should not be negative")
      end

      def _assert_in_epsilon_message(expected_float, actual_float, epsilon,
                                     message, options={})
        normalized_expected = expected_float.to_f
        normalized_actual = actual_float.to_f
        normalized_epsilon = epsilon.to_f
        delta = normalized_expected * normalized_epsilon

        if options[:negative_assertion]
          format = <<-EOT
<?> -/+ (<?> * <?>)[?] was expected to not include
<?>.
EOT
        else
          format = <<-EOT
<?> -/+ (<?> * <?>)[?] was expected to include
<?>.
EOT
        end
        arguments = [expected_float, expected_float, epsilon, delta,
                     actual_float]

        relation_format = nil
        relation_arguments = nil
        if normalized_actual < normalized_expected - delta
          relation_format = "<<?> < <?>-(<?>*<?>)[?] <= <?>+(<?>*<?>)[?]>"
          relation_arguments = [actual_float,
                                expected_float, expected_float, epsilon,
                                normalized_expected - delta,
                                expected_float, expected_float, epsilon,
                                normalized_expected + delta]
        elsif normalized_actual <= normalized_expected + delta
          relation_format = "<<?>-(<?>*<?>)[?] <= <?> <= <?>+(<?>*<?>)[?]>"
          relation_arguments = [expected_float, expected_float, epsilon,
                                normalized_expected - delta,
                                actual_float,
                                expected_float, expected_float, epsilon,
                                normalized_expected + delta]
        else
          relation_format = "<<?>-(<?>*<?>)[?] <= <?>+(<?>*<?>)[?] < <?>>"
          relation_arguments = [expected_float, expected_float, epsilon,
                                normalized_expected - delta,
                                expected_float, expected_float, epsilon,
                                normalized_expected + delta,
                                actual_float]
        end

        if relation_format
          format += <<-EOT

Relation:
#{relation_format}
EOT
          arguments.concat(relation_arguments)
        end

        build_message(message, format, *arguments)
      end

      public
      ##
      # Passes if the method `__send__` returns not false nor nil.
      #
      # `send_array` is composed of:
      # * A receiver
      # * A method
      # * Arguments to the method
      #
      # @example
      #   assert_send([[1, 2], :member?, 1]) # -> pass
      #   assert_send([[1, 2], :member?, 4]) # -> fail
      def assert_send(send_array, message=nil)
        _wrap_assertion do
          assert_instance_of(Array, send_array,
                             "assert_send requires an array " +
                             "of send information")
          assert_operator(send_array.size, :>=, 2,
                          "assert_send requires at least a receiver " +
                          "and a message name")
          format = <<EOT
<?> was expected to respond to
<?(*?)> with a true value but was
<?>.
EOT
          receiver, message_name, *arguments = send_array
          result = nil
          full_message =
            build_message(message,
                          format,
                          receiver,
                          AssertionMessage.literal(message_name.to_s),
                          arguments,
                          AssertionMessage.delayed_literal {result})
          assert_block(full_message) do
            result = receiver.__send__(message_name, *arguments)
            result
          end
        end
      end

      ##
      # Passes if the method `__send__` returns false or nil.
      #
      # `send_array` is composed of:
      # * A receiver
      # * A method
      # * Arguments to the method
      #
      # @example
      #   assert_not_send([[1, 2], :member?, 1]) # -> fail
      #   assert_not_send([[1, 2], :member?, 4]) # -> pass
      def assert_not_send(send_array, message=nil)
        _wrap_assertion do
          assert_instance_of(Array, send_array,
                             "assert_not_send requires an array " +
                             "of send information")
          assert_operator(send_array.size, :>=, 2,
                          "assert_not_send requires at least a receiver " +
                          "and a message name")
          format = <<EOT
<?> was expected to respond to
<?(*?)> with not a true value but was
<?>.
EOT
          receiver, message_name, *arguments = send_array
          result = nil
          full_message =
            build_message(message,
                          format,
                          receiver,
                          AssertionMessage.literal(message_name.to_s),
                          arguments,
                          AssertionMessage.delayed_literal {result})
          assert_block(full_message) do
            result = receiver.__send__(message_name, *arguments)
            not result
          end
        end
      end

      ##
      # Passes if `actual` is a boolean value.
      #
      # @example
      #   assert_boolean(true) # -> pass
      #   assert_boolean(nil)  # -> fail
      def assert_boolean(actual, message=nil)
        _wrap_assertion do
          assert_block(build_message(message,
                                     "<true> or <false> expected but was\n<?>",
                                     actual)) do
            true == actual || false == actual
          end
        end
      end

      ##
      # Passes if `actual` is true.
      #
      # @example
      #   assert_true(true)  # -> pass
      #   assert_true(:true) # -> fail
      def assert_true(actual, message=nil)
        _wrap_assertion do
          assert_block(build_message(message,
                                     "<true> expected but was\n<?>",
                                     actual)) do
            true == actual
          end
        end
      end

      ##
      # Passes if `actual` is false.
      #
      # @example
      #   assert_false(false)  # -> pass
      #   assert_false(nil)    # -> fail
      def assert_false(actual, message=nil)
        _wrap_assertion do
          assert_block(build_message(message,
                                     "<false> expected but was\n<?>",
                                     actual)) do
            false == actual
          end
        end
      end

      ##
      # Passes if expression "`expected` `operator`
      # `actual`" is not false nor nil.
      #
      # @example
      #   assert_compare(1, "<", 10)  # -> pass
      #   assert_compare(1, ">=", 10) # -> fail
      def assert_compare(expected, operator, actual, message=nil)
        _wrap_assertion do
          assert_send([["<", "<=", ">", ">="], :include?, operator.to_s])
          case operator.to_s
          when "<"
            operator_description = "less than"
          when "<="
            operator_description = "less than or equal to"
          when ">"
            operator_description = "greater than"
          when ">="
            operator_description = "greater than or equal to"
          end
          template = <<-EOT
<?> #{operator} <?> should be true
<?> was expected to be #{operator_description}
<?>.
EOT
          full_message = build_message(message, template,
                                       expected, actual,
                                       expected, actual)
          assert_block(full_message) do
            expected.__send__(operator, actual)
          end
        end
      end

      ##
      # Passes if assertion is failed in block.
      #
      # @example
      #   assert_fail_assertion {assert_equal("A", "B")}  # -> pass
      #   assert_fail_assertion {assert_equal("A", "A")}  # -> fail
      def assert_fail_assertion(message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "Failed assertion was expected.")
          assert_block(full_message) do
            begin
              yield
              false
            rescue AssertionFailedError
              true
            end
          end
        end
      end

      ##
      # Passes if an exception is raised in block and its
      # message is `expected`.
      #
      # @example
      #   assert_raise_message("exception") {raise "exception"}  # -> pass
      #   assert_raise_message(/exc/i) {raise "exception"}       # -> pass
      #   assert_raise_message("exception") {raise "EXCEPTION"}  # -> fail
      #   assert_raise_message("exception") {}                   # -> fail
      def assert_raise_message(expected, message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "<?> exception message was expected " +
                                       "but none was thrown.",
                                       expected)
          exception = nil
          assert_block(full_message) do
            begin
              yield
              false
            rescue Exception => exception
              true
            end
          end

          actual = exception.message
          diff = AssertionMessage.delayed_diff(expected, actual)
          full_message =
            build_message(message,
                          "<?> exception message expected but was\n" +
                          "<?>.?", expected, actual, diff)
          assert_block(full_message) do
            if expected.is_a?(Regexp)
              expected =~ actual
            else
              expected == actual
            end
          end
        end
      end

      ##
      # Passes if `object`.const_defined?(`constant_name`)
      #
      # @example
      #   assert_const_defined(Test, :Unit)          # -> pass
      #   assert_const_defined(Object, :Nonexistent) # -> fail
      def assert_const_defined(object, constant_name, message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "<?>.const_defined\\?(<?>) expected.",
                                       object, constant_name)
          assert_block(full_message) do
            object.const_defined?(constant_name)
          end
        end
      end

      ##
      # Passes if !`object`.const_defined?(`constant_name`)
      #
      # @example
      #   assert_not_const_defined(Object, :Nonexistent) # -> pass
      #   assert_not_const_defined(Test, :Unit)          # -> fail
      def assert_not_const_defined(object, constant_name, message=nil)
        _wrap_assertion do
          full_message = build_message(message,
                                       "!<?>.const_defined\\?(<?>) expected.",
                                       object, constant_name)
          assert_block(full_message) do
            !object.const_defined?(constant_name)
          end
        end
      end

      ##
      # Passes if `object`.`predicate` is not false nor nil.
      #
      # @example
      #   assert_predicate([], :empty?)  # -> pass
      #   assert_predicate([1], :empty?) # -> fail
      def assert_predicate(object, predicate, message=nil)
        _wrap_assertion do
          assert_respond_to(object, predicate, message)
          actual = object.__send__(predicate)
          full_message = build_message(message,
                                       "<?>.? is true value expected but was\n" +
                                       "<?>",
                                       object,
                                       AssertionMessage.literal(predicate),
                                       actual)
          assert_block(full_message) do
            actual
          end
        end
      end

      ##
      # Passes if `object`.`predicate` is false or nil.
      #
      # @example
      #   assert_not_predicate([1], :empty?) # -> pass
      #   assert_not_predicate([], :empty?)  # -> fail
      def assert_not_predicate(object, predicate, message=nil)
        _wrap_assertion do
          assert_respond_to(object, predicate, message)
          actual = object.__send__(predicate)
          full_message = build_message(message,
                                       "<?>.? is false value expected but was\n" +
                                       "<?>",
                                       object,
                                       AssertionMessage.literal(predicate),
                                       actual)
          assert_block(full_message) do
            not actual
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_predicate, :assert_not_predicate

      ##
      # Passes if `object`#`alias_name` is an alias method of
      # `object`#`original_name`.
      #
      # @example
      #   assert_alias_method([], :length, :size)  # -> pass
      #   assert_alias_method([], :size, :length)  # -> pass
      #   assert_alias_method([], :each, :size)    # -> fail
      def assert_alias_method(object, alias_name, original_name, message=nil)
        _wrap_assertion do
          find_method_failure_message = Proc.new do |method_name|
            build_message(message,
                          "<?>.? doesn't exist\n" +
                          "(Class: <?>)",
                          object,
                          AssertionMessage.literal(method_name),
                          object.class)
          end

          alias_method = original_method = nil
          assert_block(find_method_failure_message.call(alias_name)) do
            begin
              alias_method = object.method(alias_name)
              true
            rescue NameError
              false
            end
          end
          assert_block(find_method_failure_message.call(original_name)) do
            begin
              original_method = object.method(original_name)
              true
            rescue NameError
              false
            end
          end

          full_message = build_message(message,
                                       "<?> is alias of\n" +
                                       "<?> expected",
                                       alias_method,
                                       original_method)
          assert_block(full_message) do
            alias_method == original_method
          end
        end
      end

      ##
      # Passes if `path` exists.
      #
      # @example
      #   assert_path_exist("/tmp")          # -> pass
      #   assert_path_exist("/bin/sh")       # -> pass
      #   assert_path_exist("/nonexistent")  # -> fail
      def assert_path_exist(path, message=nil)
        _wrap_assertion do
          failure_message = build_message(message,
                                          "<?> was expected to exist",
                                          path)
          assert_block(failure_message) do
            File.exist?(path)
          end
        end
      end

      ##
      # Passes if `path` doesn't exist.
      #
      # @example
      #   assert_path_not_exist("/nonexistent")  # -> pass
      #   assert_path_not_exist("/tmp")          # -> fail
      #   assert_path_not_exist("/bin/sh")       # -> fail
      def assert_path_not_exist(path, message=nil)
        _wrap_assertion do
          failure_message = build_message(message,
                                          "<?> was expected to not exist",
                                          path)
          assert_block(failure_message) do
            not File.exist?(path)
          end
        end
      end

      ##
      # Passes if `collection` includes `object`.
      #
      # @example
      #   assert_include([1, 10], 1)            # -> pass
      #   assert_include(1..10, 5)              # -> pass
      #   assert_include([1, 10], 5)            # -> fail
      #   assert_include(1..10, 20)             # -> fail
      def assert_include(collection, object, message=nil)
        _wrap_assertion do
          assert_respond_to(collection, :include?,
                            "The collection must respond to :include?.")
          full_message = build_message(message,
                                       "<?> was expected to include\n<?>.",
                                       collection,
                                       object)
          assert_block(full_message) do
            collection.include?(object)
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 2.5.3
      alias_method :assert_includes, :assert_include

      ##
      # Passes if `collection` doesn't include `object`.
      #
      # @example
      #   assert_not_include([1, 10], 5)            # -> pass
      #   assert_not_include(1..10, 20)             # -> pass
      #   assert_not_include([1, 10], 1)            # -> fail
      #   assert_not_include(1..10, 5)              # -> fail
      def assert_not_include(collection, object, message=nil)
        _wrap_assertion do
          assert_respond_to(collection, :include?,
                            "The collection must respond to :include?.")
          full_message = build_message(message,
                                       "<?> was expected to not include\n<?>.",
                                       collection,
                                       object)
          assert_block(full_message) do
            not collection.include?(object)
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :assert_not_includes, :assert_not_include

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_includes, :assert_not_include

      ##
      # Passes if `object` is empty.
      #
      # @example
      #   assert_empty("")                       # -> pass
      #   assert_empty([])                       # -> pass
      #   assert_empty({})                       # -> pass
      #   assert_empty(" ")                      # -> fail
      #   assert_empty([nil])                    # -> fail
      #   assert_empty({1 => 2})                 # -> fail
      def assert_empty(object, message=nil)
        _wrap_assertion do
          assert_respond_to(object, :empty?,
                            "The object must respond to :empty?.")
          full_message = build_message(message,
                                       "<?> was expected to be empty.",
                                       object)
          assert_block(full_message) do
            object.empty?
          end
        end
      end

      ##
      # Passes if `object` is not empty.
      #
      # @example
      #   assert_not_empty(" ")                      # -> pass
      #   assert_not_empty([nil])                    # -> pass
      #   assert_not_empty({1 => 2})                 # -> pass
      #   assert_not_empty("")                       # -> fail
      #   assert_not_empty([])                       # -> fail
      #   assert_not_empty({})                       # -> fail
      def assert_not_empty(object, message=nil)
        _wrap_assertion do
          assert_respond_to(object, :empty?,
                            "The object must respond to :empty?.")
          full_message = build_message(message,
                                       "<?> was expected to not be empty.",
                                       object)
          assert_block(full_message) do
            not object.empty?
          end
        end
      end

      # Just for minitest compatibility. :<
      #
      # @since 3.0.0
      alias_method :refute_empty, :assert_not_empty

      # @overload assert_all(collection, message=nil, &block)
      #
      #   Asserts that all `block.call(item)` where `item` is each
      #   item in `collection` are not false nor nil.
      #
      #   If `collection` is empty, this assertion is always passed
      #   with any `block`.
      #
      #   @example Pass patterns
      #     assert_all([1, 2, 3]) {|item| item > 0} # => pass
      #     assert_all([1, 2, 3], &:positive?)      # => pass
      #     assert_all([]) {|item| false}           # => pass
      #
      #   @example Failure pattern
      #     assert_all([0, 1, 2], &:zero?) # => failure
      #
      #   @param [#each] collection The check target.
      #   @param [String] message The additional user message. It is
      #     showed when the assertion is failed.
      #   @yield [Object] Give each item in `collection` to the block.
      #   @yieldreturn [Object] The checked object.
      #   @return [void]
      #
      # @since 3.4.4
      def assert_all(collection, message=nil)
        _wrap_assertion do
          failed = false
          result = {}
          collection.each do |item|
            element_result = yield(item)
            failed = true unless element_result
            result[item] = element_result
          end
          format = <<-FORMAT
<?> was expected to be all true values with the given block but was
<?>
          FORMAT
          full_message = build_message(message,
                                       format,
                                       collection,
                                       result)
          assert_block(full_message) do
            not failed
          end
        end
      end

      # Just for Ruby's tool/lib/test/unit compatibility.
      #
      # @since 3.4.3
      alias_method :assert_all?, :assert_all

      # @overload assert_nothing_leaked_memory(max_increasable_size, target=:physical, message=nil, &block)
      #
      #   Asserts that increased memory usage by `block.call` is less
      #   than `max_increasable_size`. `GC.start` is called before and
      #   after `block.call`.
      #
      #   This assertion may be fragile. Because memory usage is
      #   depends on the current Ruby process's memory
      #   usage. Launching a new Ruby process for this will produce
      #   more stable result but we need to specify target code as
      #   `String` instead of block for the approach. We choose easy
      #   to write API approach rather than more stable result
      #   approach for this case.
      #
      #   @example Pass pattern
      #     require "objspace"
      #     size_per_object = ObjectSpace.memsize_of("Hello")
      #     # If memory isn't leaked, physical memory of almost created objects
      #     # (1000 - 10 objects) must be freed.
      #     assert_nothing_leaked_memory(size_per_object * 10) do
      #       1_000.times do
      #         "Hello".dup
      #       end
      #     end # => pass
      #
      #   @example Failure pattern
      #     require "objspace"
      #     size_per_object = ObjectSpace.memsize_of("Hello")
      #     strings = []
      #     assert_nothing_leaked_memory(size_per_object * 10) do
      #       10_000.times do
      #         # Created objects aren't GC-ed because they are referred.
      #         strings << "Hello".dup
      #       end
      #     end # => failure
      #
      #   @param target [:physical, :virtual] which memory usage is
      #     used for comparing. `:physical` means physical memory usage
      #     also known as Resident Set Size (RSS). `:virtual` means
      #     virtual memory usage.
      #   @yield [] do anything you want to measure memory usage
      #     in the block.
      #   @yieldreturn [void]
      #   @return [void]
      #
      # @since 3.4.5
      def assert_nothing_leaked_memory(max_increasable_size,
                                       target=:physical,
                                       message=nil)
        _wrap_assertion do
          GC.start
          before = Util::MemoryUsage.new
          unless before.collected?
            omit("memory usage collection isn't supported on this platform")
          end
          yield
          GC.start
          after = Util::MemoryUsage.new
          before_value = before.__send__(target)
          after_value = after.__send__(target)
          actual_increased_size = after_value - before_value
          template = <<-TEMPLATE
<?> was expected to be less than
<?>.
          TEMPLATE
          full_message = build_message(message,
                                       template,
                                       actual_increased_size,
                                       max_increasable_size)
          assert_block(full_message) do
            actual_increased_size < max_increasable_size
          end
        end
      end

      ##
      # Builds a failure message.  `user_message` is added before the
      # `template` and `arguments` replaces the '?'s positionally in
      # the template.
      def build_message(user_message, template=nil, *arguments)
        template &&= template.chomp
        return AssertionMessage.new(user_message, template, arguments)
      end

      private
      def _wrap_assertion(&block)
        @_assertion_wrapped ||= false
        if @_assertion_wrapped
          block.call
        else
          @_assertion_wrapped = true
          begin
            add_assertion
            block.call
          ensure
            @_assertion_wrapped = false
          end
        end
      end

      public
      # Called whenever an assertion is made. Define this in classes
      # that include Test::Unit::Assertions to record assertion
      # counts.
      #
      # This is a public API for developers who extend test-unit.
      #
      # @return [void]
      def add_assertion
      end

      ##
      # Select whether or not to use the pretty-printer. If this option is set
      # to false before any assertions are made, pp.rb will not be required.
      def self.use_pp=(value)
        AssertionMessage.use_pp = value
      end

      private
      def _assert_raise(assert_expected_exception, *args, &block)
        _wrap_assertion do
          if args.last.is_a?(String)
            message = args.pop
          else
            message = ""
          end

          assert_exception_helper = AssertExceptionHelper.new(self, args)
          expected = assert_exception_helper.expected_exceptions
          actual_exception = nil
          full_message = build_message(message,
                                       "<?> exception was expected " +
                                       "but none was thrown.",
                                       expected)
          assert_block(full_message) do
            begin
              yield
              false
            rescue Exception => actual_exception
              true
            end
          end
          assert_expected_exception.call(message, assert_exception_helper,
                                         actual_exception)
          actual_exception
        end
      end

      def _set_failed_information(failure, expected, actual)
        failure.expected = expected
        failure.actual = actual
        failure.inspected_expected = AssertionMessage.convert(expected)
        failure.inspected_actual = AssertionMessage.convert(actual)
      end

      class AssertionMessage
        @use_pp = true
        class << self
          attr_accessor :use_pp

          def literal(value)
            Literal.new(value)
          end

          def delayed_literal(&block)
            DelayedLiteral.new(block)
          end

          def maybe_container(value, &formatter)
            MaybeContainer.new(value, &formatter)
          end

          MAX_DIFF_TARGET_STRING_SIZE = 1000
          def max_diff_target_string_size
            return @@max_diff_target_string_size if @@max_diff_target_string_size

            size = ENV["TEST_UNIT_MAX_DIFF_TARGET_STRING_SIZE"]
            if size
              begin
                size = Integer(size)
              rescue ArgumentError
                size = nil
              end
            end
            size || MAX_DIFF_TARGET_STRING_SIZE
          end

          @@max_diff_target_string_size = nil
          def max_diff_target_string_size=(size)
            @@max_diff_target_string_size = size
          end

          def diff_target_string?(string)
            if string.respond_to?(:bytesize)
              string.bytesize < max_diff_target_string_size
            else
              string.size < max_diff_target_string_size
            end
          end

          def ensure_diffable_string(string)
            if string.respond_to?(:encoding) and
                !string.encoding.ascii_compatible?
              string = string.dup.force_encoding("ASCII-8BIT")
            end
            string
          end

          def prepare_for_diff(from, to)
            if !from.is_a?(String) or !to.is_a?(String)
              from = convert(from)
              to = convert(to)
            end

            if diff_target_string?(from) and diff_target_string?(to)
              from = ensure_diffable_string(from)
              to = ensure_diffable_string(to)
              [from, to]
            else
              [nil, nil]
            end
          end

          def delayed_diff(from, to)
            delayed_literal do
              from, to = prepare_for_diff(from, to)

              diff = "" if from.nil? or to.nil?
              diff ||= Diff.readable(from, to)
              if /^[-+]/ !~ diff
                diff = ""
              elsif /^[ ?]/ =~ diff or /(?:.*\n){2,}/ =~ diff
                diff = "\n\ndiff:\n#{diff}"
              else
                diff = ""
              end

              if Diff.need_fold?(diff)
                folded_diff = Diff.folded_readable(from, to)
                diff += "\n\nfolded diff:\n#{folded_diff}"
              end

              diff
            end
          end

          def convert(object)
            if object.is_a?(Exception)
              object = AssertExceptionHelper::WrappedException.new(object)
            end
            inspector = Inspector.new(object)
            if use_pp
              begin
                require "pp" unless defined?(PP)
                begin
                  return PP.pp(inspector, String.new).chomp
                rescue NameError
                end
              rescue LoadError
                self.use_pp = false
              end
            end
            inspector.inspect
          end
        end

        class Inspector
          include Comparable

          class << self
            def cached_new(object, inspected_objects)
              inspected_objects[object.object_id] ||=
                new(object, inspected_objects)
            end

            @@inspector_classes = []
            def inspector_classes
              @@inspector_classes
            end

            def register_inspector_class(inspector_class)
              @@inspector_classes << inspector_class
            end

            def unregister_inspector_class(inspector_class)
              @@inspector_classes.delete(inspector_class)
            end
          end

          attr_reader :object
          def initialize(object, inspected_objects={})
            @inspected_objects = inspected_objects
            @object = object
            @inspected_objects[@object.object_id] = self
            @inspect_target = inspect_target
          end

          alias_method :native_inspect, :inspect
          def inspect
            @inspect_target.inspect
          end

          def pretty_print(q)
            @inspect_target.pretty_print(q)
          end

          def pretty_print_cycle(q)
            @inspect_target.pretty_print_cycle(q)
          end

          def <=>(other)
            if other.is_a?(self.class)
              @object <=> other.object
            else
              @object <=> other
            end
          end

          private
          def inspect_target
            self.class.inspector_classes.each do |inspector_class|
              if inspector_class.target?(@object)
                return inspector_class.new(@object, @inspected_objects)
              end
            end
            @object
          end
        end

        class NumericInspector
          Inspector.register_inspector_class(self)

          class << self
            def target?(object)
              object.is_a?(Numeric)
            end
          end

          def initialize(numeric, inspected_objects)
            @inspected_objects = inspected_objects
            @numeric = numeric
          end

          def inspect
            @numeric.to_s
          end

          def pretty_print(q)
            q.text(@numeric.to_s)
          end

          def pretty_print_cycle(q)
            q.text(@numeric.to_s)
          end
        end

        class HashInspector
          Inspector.register_inspector_class(self)

          class << self
            def target?(object)
              object.is_a?(Hash) or ENV.equal?(object)
            end
          end

          def initialize(hash, inspected_objects)
            @inspected_objects = inspected_objects
            @hash = {}
            hash.each do |key, value|
              key = Inspector.cached_new(key, @inspected_objects)
              value = Inspector.cached_new(value, @inspected_objects)
              @hash[key] = value
            end
          end

          def inspect
            @hash.inspect
          end

          def pretty_print(q)
            q.group(1, '{', '}') do
              q.seplist(self, nil, :each_pair) do |k, v|
                q.group do
                  q.pp(k)
                  q.text('=>')
                  q.group(1) do
                    q.breakable('')
                    q.pp(v)
                  end
                end
              end
            end
          end

          def pretty_print_cycle(q)
            @hash.pretty_print_cycle(q)
          end

          def each_pair
            keys = @hash.keys
            begin
              keys = keys.sort # FIXME: more cleverly
            rescue ArgumentError
            end
            keys.each do |key|
              yield(key, @hash[key])
            end
          end
        end

        class ArrayInspector
          Inspector.register_inspector_class(self)

          class << self
            def target?(object)
              object.is_a?(Array)
            end
          end

          def initialize(array, inspected_objects)
            @inspected_objects = inspected_objects
            @array = array.collect do |element|
              Inspector.cached_new(element, @inspected_objects)
            end
          end

          def inspect
            @array.inspect
          end

          def pretty_print(q)
            q.group(1, '[', ']') do
              q.seplist(self) do |v|
                q.pp(v)
              end
            end
          end

          def pretty_print_cycle(q)
            @array.pretty_print_cycle(q)
          end

          def each(&block)
            @array.each(&block)
          end
        end

        class Literal
          def initialize(value)
            @value = value
          end

          def inspect
            @value.to_s
          end
        end

        class DelayedLiteral
          def initialize(value)
            @value = value
          end

          def inspect
            @value.call.to_s
          end
        end

        class MaybeContainer
          def initialize(value, &formatter)
            @value = value
            @formatter = formatter
          end

          def inspect
            if @value.is_a?(Array)
              values = @value.collect do |value|
                @formatter.call(AssertionMessage.convert(value))
              end
              "[#{values.join(', ')}]"
            else
              @formatter.call(AssertionMessage.convert(@value))
            end
          end
        end

        class Template
          def self.create(string)
            parts = (string ? string.scan(/(?=[^\\])\?|(?:\\\?|[^\?])+/m) : [])
            self.new(parts)
          end

          attr_reader :count

          def initialize(parts)
            @parts = parts
            @count = parts.find_all{|e| e == '?'}.size
          end

          def result(parameters)
            raise "The number of parameters does not match the number of substitutions." if(parameters.size != count)
            params = parameters.dup
            expanded_template = ""
            @parts.each do |part|
              if part == '?'
                param = params.shift
                if Object.const_defined?(:Encoding)
                  expanded_template += concatenatable(param,
                                                      expanded_template.encoding)
                else
                  expanded_template += param
                end
              else
                expanded_template += part.gsub(/\\\?/m, '?')
              end
            end
            expanded_template
          end

          private
          def concatenatable(text, encoding)
            if Encoding.compatible?(text, encoding)
              text
            else
              text.dup.force_encoding(encoding)
            end
          end
        end

        include Util::BacktraceFilter

        def initialize(user_message, template_string, parameters)
          @user_message = user_message
          @template_string = template_string
          @parameters = parameters
        end

        def convert(object)
          self.class.convert(object)
        end

        def template
          @template ||= Template.create(@template_string)
        end

        def user_message
          return nil unless @user_message
          message = @user_message
          message = message.call if message.respond_to?(:call)
          message.to_s
        end

        def to_s
          message_parts = []
          head = user_message
          if head and not head.empty?
            message_parts << add_period(head)
          end
          tail = template.result(@parameters.collect{|e| convert(e)})
          message_parts << tail unless(tail.empty?)
          message_parts.join("\n")
        end

        private
        def add_period(string)
          (string =~ /\.\Z/ ? string : string + '.')
        end
      end

      class AssertExceptionHelper
        class WrappedException
          attr_reader :exception
          def initialize(exception)
            @exception = exception
          end

          def inspect
            if default_inspect?
              inspected = "#{@exception.class.inspect}(<#{@exception.message}>)"
              unless (@exception.backtrace || []).empty?
                inspected += "\n"
                @exception.backtrace.each do |trace|
                  inspected << "#{trace}\n"
                end
              end
              inspected
            else
              @exception.inspect
            end
          end

          def method_missing(name, *args, &block)
            @exception.__send__(name, *args, &block)
          end

          private
          def default_inspect?
            inspect_method = @exception.method(:inspect)
            if inspect_method.respond_to?(:owner) and
                inspect_method.owner == Exception
              true
            else
              default_inspect_method = Exception.instance_method(:inspect)
              default_inspect_method.bind(@exception).call == @exception.inspect
            end
          end
        end

        def initialize(test_case, expected_exceptions)
          @test_case = test_case
          @expected_exceptions = expected_exceptions
          @expected_classes, @expected_modules, @expected_objects =
            split_expected_exceptions(expected_exceptions)
        end

        def expected_exceptions
          exceptions = @expected_exceptions.collect do |exception|
            if exception.is_a?(Exception)
              WrappedException.new(exception)
            else
              exception
            end
          end
          if exceptions.size == 1
            exceptions[0]
          else
            exceptions
          end
        end

        def expected?(actual_exception, equality=nil)
          equality ||= :instance_of?
          expected_class?(actual_exception, equality) or
            expected_module?(actual_exception) or
            expected_object?(actual_exception)
        end

        private
        def split_expected_exceptions(expected_exceptions)
          exception_modules = []
          exception_objects = []
          exception_classes = []
          expected_exceptions.each do |exception_type|
            if exception_type.instance_of?(Module)
              exception_modules << exception_type
            elsif exception_object?(exception_type)
              exception_objects << exception_type
            elsif exception_class?(exception_type)
              exception_classes << exception_type
            else
              full_message =
                @test_case.__send__(:build_message,
                                    nil,
                                    "<?> must be " +
                                    "a subclass of Exception, " +
                                    "an object of Exception subclasses " +
                                    "or a Module",
                                    exception_type)
              @test_case.flunk(full_message)
            end
          end
          [exception_classes, exception_modules, exception_objects]
        end

        def exception_object?(exception_type)
          return true if exception_type.is_a?(Exception)

          if Object.const_defined?(:Java)
            return true if exception_type.is_a?(Java::JavaLang::Throwable)
          end

          false
        end

        def exception_class?(exception_type)
          return true if exception_type <= Exception

          if Object.const_defined?(:Java)
            return true if exception_type <= Java::JavaLang::Throwable
          end

          false
        end

        def expected_class?(actual_exception, equality)
          @expected_classes.any? do |expected_class|
            actual_exception.__send__(equality, expected_class)
          end
        end

        def expected_module?(actual_exception)
          @expected_modules.any? do |expected_module|
            actual_exception.is_a?(expected_module)
          end
        end

        def expected_object?(actual_exception)
          @expected_objects.any? do |expected_object|
            expected_object == actual_exception or
              fallback_exception_object_equal(expected_object, actual_exception)
          end
        end

        def fallback_exception_object_equal(expected_object, actual_exception)
          owner = Util::MethodOwnerFinder.find(expected_object, :==)
          if owner == Kernel or owner == Exception
            expected_object.class == actual_exception.class and
              expected_object.message == actual_exception.message
          else
            false
          end
        end
      end

      # :startdoc:
    end
  end
end
