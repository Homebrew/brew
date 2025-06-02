#--
#
# Author:: Nathaniel Talbott.
# Copyright::
#   * Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
#   * Copyright (c) 2008-2012 Kouhei Sutou <tt><kou@clear-code.com></tt>
# License:: Ruby license.

require 'test/unit/attribute'
require 'test/unit/fixture'
require 'test/unit/exception-handler'
require 'test/unit/assertions'
require 'test/unit/failure'
require 'test/unit/error'
require 'test/unit/pending'
require 'test/unit/omission'
require 'test/unit/notification'
require 'test/unit/priority'
require 'test/unit/data'
require 'test/unit/testsuite'
require 'test/unit/test-suite-creator'
require 'test/unit/assertion-failed-error'
require 'test/unit/auto-runner-loader'
require 'test/unit/util/backtracefilter'
require 'test/unit/util/output'
require 'test/unit/util/method-owner-finder'

module Test
  module Unit

    # Ties everything together. If you subclass and add your own
    # test methods, it takes care of making them into tests and
    # wrapping those tests into a suite. It also does the
    # nitty-gritty of actually running an individual test and
    # collecting its results into a Test::Unit::TestResult object.
    #
    # You can run two hooks before/after a TestCase run.
    #
    # Example:
    #
    #     class TestMyClass < Test::Unit::TestCase
    #       class << self
    #         def startup
    #           ...
    #         end
    #
    #         def shutdown
    #           ...
    #         end
    #       end
    #
    #       def setup
    #         ...
    #       end
    #
    #       def cleanup
    #         ...
    #       end
    #
    #       def teardown
    #         ...
    #       end
    #
    #       def test_my_method1
    #         ...
    #       end
    #
    #       def test_my_method2
    #         ...
    #       end
    #     end
    #
    # Here is a call order:
    #
    # 1. startup
    # 1. setup
    # 1. test_my_method1
    # 1. cleanup
    # 1. teardown
    # 1. setup
    # 1. test_my_method2
    # 1. cleanup
    # 1. teardown
    # 1. shutdown
    #
    # You can set an attribute to each test.
    #
    # Example:
    #
    #     class TestMyClass < Test::Unit::TestCase
    #       attribute :speed, :fast
    #       def test_my_fast_method
    #         # You can get the attribute via `self[]`
    #         self[:speed] # => :fast
    #         ...
    #       end
    #
    #       attribute :speed, :slow
    #       def test_my_slow_method
    #         self[:speed] # => :slow
    #         ...
    #       end
    #     end
    class TestCase
      include Attribute
      include Fixture
      include ExceptionHandler
      include ErrorHandler
      include FailureHandler
      include TestCasePendingSupport
      include TestCaseOmissionSupport
      include TestCaseNotificationSupport
      include Priority
      include Data
      include Assertions
      include Util::BacktraceFilter
      include Util::Output

      STARTED = name + "::STARTED" # :nodoc:
      FINISHED = name + "::FINISHED" # :nodoc:
      STARTED_OBJECT = name + "::STARTED::OBJECT" # :nodoc:
      FINISHED_OBJECT = name + "::FINISHED::OBJECT" # :nodoc:

      DESCENDANTS = [] # :nodoc:
      AVAILABLE_ORDERS = [:alphabetic, :random, :defined] # :nodoc:

      class << self
        def inherited(sub_class) # :nodoc:
          DESCENDANTS << sub_class
          super
        end

        def include(*modules, &block) # :nodoc:
          result = super
          modules.each do |mod|
            mod.public_instance_methods(false).each do |method_name|
              AutoRunnerLoader.check(self, method_name.to_s)
            end
          end
          result
        end

        @@added_method_names = {}
        def method_added(name) # :nodoc:
          super
          added_method_names = (@@added_method_names[self] ||= {})
          stringified_name = name.to_s
          if added_method_names.key?(stringified_name)
            attribute(:redefined, {:backtrace => caller}, {}, stringified_name)
          end
          source_location = find_attribute(stringified_name, :source_location)
          if source_location
            path, line = source_location
          elsif respond_to?(:caller_locations, true)
            location = caller_locations(1, 1)[0]
            path = location.absolute_path || location.path
            line = location.lineno
          else
            # TODO: Remove me when Ruby 1.9 support is dropped
            path, line, = caller[0].split(/:(\d+)/, 2)
            line = line.to_i if line
          end
          location = {
            :method_name => stringified_name,
            :path => File.expand_path(path),
            :line => line,
          }
          add_method_location(location)
          added_method_names[stringified_name] = true
          AutoRunnerLoader.check(self, stringified_name)
        end

        def added_method_names # :nodoc:
          (@@added_method_names[self] ||= {}).keys
        end

        # Rolls up all of the test* methods in the fixture into
        # one suite, creating a new instance of the fixture for
        # each method.
        def suite
          suite_creator = TestSuiteCreator.new(self)
          suite_creator.create
        end

        # Called before every test case runs. Can be used
        # to set up fixture information used in test case
        # scope.
        #
        # Here is an example test case:
        #
        #     class TestMyClass < Test::Unit::TestCase
        #       class << self
        #         def startup
        #           ...
        #         end
        #       end
        #
        #       def setup
        #         ...
        #       end
        #
        #       def test_my_class1
        #         ...
        #       end
        #
        #       def test_my_class2
        #         ...
        #       end
        #     end
        #
        # Here is a call order:
        #
        # * startup
        # * setup
        # * test_my_class1 (or test_my_class2)
        # * setup
        # * test_my_class2 (or test_my_class1)
        #
        # Note that you should not assume test order. Tests
        # should be worked in any order.
        def startup
        end

        # Called after every test case runs. Can be used to tear
        # down fixture information used in test case scope.
        #
        # Here is an example test case:
        #
        #     class TestMyClass < Test::Unit::TestCase
        #       class << self
        #         def shutdown
        #           ...
        #         end
        #       end
        #
        #       def teardown
        #         ...
        #       end
        #
        #       def test_my_class1
        #         ...
        #       end
        #
        #       def test_my_class2
        #         ...
        #       end
        #     end
        #
        # Here is a call order:
        #
        # * test_my_class1 (or test_my_class2)
        # * teardown
        # * test_my_class2 (or test_my_class1)
        # * teardown
        # * shutdown
        #
        # Note that you should not assume test order. Tests
        # should be worked in any order.
        def shutdown
        end

        @@test_orders = {}

        # Returns the current test order. This returns
        # `:alphabetic` by default.
        def test_order
          ancestors.each do |ancestor|
            order = @@test_orders[ancestor]
            return order if order
          end
          AVAILABLE_ORDERS.first
        end

        # Sets the current test order.
        #
        # Here are the available _order_:
        #
        # :alphabetic
        # : Default. Tests are sorted in alphabetic order.
        #
        # :random
        # : Tests are sorted in random order.
        #
        # :defined
        # : Tests are sorted in defined order.
        def test_order=(order)
          @@test_orders[self] = order
        end

        # Defines a test in declarative syntax or marks
        # following method as a test method.
        #
        # In declarative syntax usage, the following two
        # test definitions are the almost same:
        #
        #     description "register user"
        #     def test_register_user
        #       ...
        #     end
        #
        #     test "register user" do
        #       ...
        #     end
        #
        # In test method mark usage, the "my_test_method" is
        # treated as a test method:
        #
        #     test
        #     def my_test_method
        #       assert_equal("call me", ...)
        #     end
        def test(*test_description_or_targets, &block)
          if block_given?
            test_description = test_description_or_targets.first
            if test_description.nil?
              raise ArgumentError, "test description is missing"
            end
            n_arguments = test_description_or_targets.size
            if n_arguments > 1
              message = "wrong number of arguments (#{n_arguments} for 1)"
              raise ArgumentError, message
            end
            method_name = "test: #{test_description}"
            description(test_description, method_name)
            attribute(:test, true, {}, method_name)
            if block.respond_to?(:source_location)
              attribute(:source_location, block.source_location, {}, method_name)
            end
            define_method(method_name, &block)
          else
            targets = test_description_or_targets
            attribute(:test, true, {}, *targets)
            targets.each do |target|
              AutoRunnerLoader.check(self, target)
            end
          end
        end

        # Describes a test.
        #
        # The following example associates "register a
        # normal user" description with "test_register"
        # test.
        #
        #     description "register a normal user"
        #     def test_register
        #       ...
        #     end
        def description(value, target=nil)
          targets = [target].compact
          attribute(:description, value, {}, *targets)
        end

        # Declares that the following test uses Ractor.
        #
        # Tests that use Ractor are executed at the end. Because multi
        # Ractor mode is enabled in the current process and it's not
        # disabled even when only one Ractor is running after running
        # a test that uses Ractor on Ruby 3.0. It will be solved in
        # Ruby 3.1.
        #
        # This is implemented by setting the `:ractor` attribute of
        # the test to `true`.
        #
        # @param options [Hash] See {Attribute::ClassMethods#attribute}
        #   for details.
        #
        # @return [void]
        #
        # @example Declares that test_do_something_with_ractor uses Ractor
        #
        #   ractor
        #   def test_do_something_with_ractor
        #     Ractor.new do
        #       # ...
        #     end
        #   end
        #
        # @since 3.4.6
        def ractor(options={})
          attribute(:ractor, true, options)
        end

        # Defines a sub test case.
        #
        # This is a syntax sugar. The both of the following codes are
        # the same in meaning:
        #
        # Standard:
        #
        #     class TestParent < Test::Unit::TestCase
        #       class TestChild < self
        #         def test_in_child
        #         end
        #       end
        #     end
        #
        # Syntax sugar:
        #
        #     class TestParent < Test::Unit::TestCase
        #       sub_test_case("TestChild") do
        #         def test_in_child
        #         end
        #       end
        #     end
        #
        # The difference of them are the following:
        #
        # * Test case created by {sub_test_case} is an anonymous class.
        #   So you can't refer the test case by name.
        # * The class name of class style must follow
        #   constant naming rule in Ruby. But the name of test case
        #   created by {sub_test_case} doesn't need to follow the rule.
        #   For example, you can use a space in name such as "child test".
        #
        # @param name [String] The name of newly created sub test case.
        # @yield
        #   The block is evaluated under the newly created sub test
        #   case class context.
        # @return [Test::Unit::TestCase] Created sub test case class.
        def sub_test_case(name, &block)
          sub_test_case = sub_test_case_class(name)
          sub_test_case.class_eval(&block)
          sub_test_case
        end

        # Checks whether a test that is matched the query is
        # defined.
        #
        # @option query [String] :path (nil)
        #   the path where a test is defined in.
        # @option query [Numeric] :line (nil)
        #   the line number where a test is defined at.
        # @option query [String] :method_name (nil)
        #   the method name for a test.
        def test_defined?(query)
          locations = find_locations(query)
          not locations.empty?
        end

        def find_locations(query)
          query_path = query[:path]
          query_line = query[:line]
          query_method_name = query[:method_name]

          available_locations = target_method_locations(query_path)
          if query_line
            available_locations = available_locations.sort_by do |location|
              -location[:line]
            end
            available_location = available_locations.find do |location|
              query_line >= location[:line]
            end
            return [] if available_location.nil?
            return [] if available_location[:test_case] != self
            available_locations = [available_location]
          end
          if query_method_name
            available_location = available_locations.find do |location|
              location[:test_case] == self and
                query_method_name == location[:method_name]
            end
            return [] if available_location.nil?
            available_locations = [available_location]
          end

          available_locations
        end

        private
        # @private
        @@method_locations = {}
        # @private
        @@method_location_mutex = Thread::Mutex.new

        # @private
        def method_locations
          @@method_locations[self] ||= []
        end

        # @private
        def add_method_location(location)
          @@method_location_mutex.synchronize do
            method_locations << location
          end
        end

        # @private
        def target_method_locations(path)
          @@method_location_mutex.synchronize do
            if path.nil?
              self_location = method_locations.first
              path = self_location[:path] if self_location
            end
            return [] if path.nil?

            target_locations = []
            @@method_locations.each do |test_case, locations|
              locations.each do |location|
                absolete_path = File.expand_path(path)
                location_path = location[:path]
                location_basename = File.basename(location_path)
                if location_path == absolete_path or location_basename == path
                  target_locations << location.merge(:test_case => test_case)
                end
              end
            end
            target_locations
          end
        end

        # @private
        def sub_test_case_class(name)
          parent_test_case = self
          Class.new(self) do
            singleton_class = class << self; self; end
            singleton_class.__send__(:define_method, :name) do
              [parent_test_case.name, name].compact.join("::")
            end
          end
        end
      end

      attr_reader :method_name

      # Creates a new instance of the fixture for running the
      # test represented by test_method_name.
      def initialize(test_method_name)
        @method_name = test_method_name
        @internal_data = InternalData.new
      end

      # Assigns test data to the test. It is used in internal.
      def assign_test_data(label, data) # :nodoc:
        @internal_data.assign_test_data(label, data)
      end

      # Returns the test is valid test. It is used in internal.
      def valid? # :nodoc:
        return false unless respond_to?(@method_name)
        test_method = method(@method_name)
        unless @internal_data.have_test_data?
          return false unless test_method.arity <= 0
        end
        owner = Util::MethodOwnerFinder.find(self, @method_name)
        if owner.class != Module and self.class != owner
          return false
        end
        true
      end

      # Runs the individual test method represented by this
      # instance of the fixture, collecting statistics, failures
      # and errors in result.
      def run(result)
        begin
          @_result = result
          @internal_data.test_started
          yield(STARTED, name)
          yield(STARTED_OBJECT, self)
          processed_exception_in_setup = false
          begin
            catch do |tag|
              run_setup do
                begin
                  run_test
                  run_cleanup
                  add_pass
                rescue Exception
                  @internal_data.interrupted
                  unless handle_exception($!)
                    processed_exception_in_setup = true
                    raise
                  end
                  throw(tag)
                end
              end
            end
          rescue Exception
            if processed_exception_in_setup
              raise
            else
              @internal_data.interrupted
              raise unless handle_exception($!)
            end
          ensure
            begin
              run_teardown
            rescue Exception
              raise unless handle_exception($!)
            end
          end
          @internal_data.test_finished
          result.add_run
          yield(FINISHED, name)
          yield(FINISHED_OBJECT, self)
        ensure
          # @_result = nil # For test-spec's after_all :<
        end
      end

      # Called before every test method runs. Can be used
      # to set up fixture information.
      #
      # You can add additional setup tasks by the following
      # code:
      #
      #     class TestMyClass < Test::Unit::TestCase
      #       def setup
      #         ...
      #       end
      #
      #       setup
      #       def my_setup1
      #         ...
      #       end
      #
      #       setup do
      #         ... # setup callback1
      #       end
      #
      #       setup
      #       def my_setup2
      #         ...
      #       end
      #
      #       setup do
      #         ... # setup callback2
      #       end
      #
      #       def test_my_class
      #         ...
      #       end
      #     end
      #
      # Here is a call order:
      #
      # * setup
      # * my_setup1
      # * setup callback1
      # * my_setup2
      # * setup callback2
      # * test_my_class
      def setup
      end

      # Called after every test method runs but the test
      # method isn't marked as 'passed'. Can be used to
      # clean up and/or verify tested condition.
      # e.g. Can be used to verify mock.
      #
      # You can add additional cleanup tasks by the following
      # code:
      #
      #     class TestMyClass < Test::Unit::TestCase
      #       def cleanup
      #         ...
      #       end
      #
      #       cleanup
      #       def my_cleanup1
      #         ...
      #       end
      #
      #       cleanup do
      #         ... # cleanup callback1
      #       end
      #
      #       cleanup
      #       def my_cleanup2
      #         ...
      #       end
      #
      #       cleanup do
      #         ... # cleanup callback2
      #       end
      #
      #       def test_my_class
      #         ...
      #       end
      #     end
      #
      # Here is a call order:
      #
      # * test_my_class
      # * cleanup callback2
      # * my_cleanup2
      # * cleanup callback1
      # * my_cleanup1
      # * cleanup
      def cleanup
      end

      # Called after every test method runs. Can be used to tear
      # down fixture information.
      #
      # You can add additional teardown tasks by the following
      # code:
      #
      #     class TestMyClass < Test::Unit::TestCase
      #       def teardown
      #         ...
      #       end
      #
      #       teardown
      #       def my_teardown1
      #         ...
      #       end
      #
      #       teardown do
      #         ... # teardown callback1
      #       end
      #
      #       teardown
      #       def my_teardown2
      #         ...
      #       end
      #
      #       teardown do
      #         ... # teardown callback2
      #       end
      #
      #       def test_my_class
      #         ...
      #       end
      #     end
      #
      # Here is a call order:
      #
      # * test_my_class
      # * teardown callback2
      # * my_teardown2
      # * teardown callback1
      # * my_teardown1
      # * teardown
      def teardown
      end

      def default_test
        flunk("No tests were specified")
      end

      def size
        1
      end

      # Returns a label of test data for the test. If the
      # test isn't associated with any test data, it returns
      # `nil`.
      def data_label
        @internal_data.test_data_label
      end

      # Returns test data for the test. If the test isn't associated
      # with any test data, it returns `nil`.
      def data
        @internal_data.test_data
      end

      # Returns a human-readable name for the specific test that
      # this instance of TestCase represents.
      def name
        "#{local_name}(#{self.class.name})"
      end

      # Returns a human-readable name for the specific test that this
      # instance of TestCase represents.
      #
      # `#local_name` doesn't include class name. `#name` includes
      # class name.
      def local_name
        if @internal_data.have_test_data?
          "#{@method_name}[#{data_label}]"
        else
          @method_name.to_s
        end
      end

      # Returns a description for the test. A description
      # will be associated by Test::Unit::TestCase.test or
      # Test::Unit::TestCase.description.
      #
      # Returns a name for the test for no description test.
      def description
        self[:description] || name
      end

      # Overridden to return #name.
      def to_s
        name
      end

      # It's handy to be able to compare TestCase instances.
      def ==(other)
        return false unless other.kind_of?(self.class)
        return false unless @method_name == other.method_name
        return false unless data_label == other.data_label
        self.class == other.class
      end

      # Returns a Time at the test was started.
      def start_time
        @internal_data.start_time
      end

      # Returns elapsed time for the test was ran.
      def elapsed_time
        @internal_data.elapsed_time
      end

      # Returns whether the test is interrupted.
      def interrupted?
        @internal_data.interrupted?
      end

      # Returns whether this individual test passed or
      # not. Primarily for use in teardown so that artifacts
      # can be left behind if the test fails.
      def passed?
        @internal_data.passed?
      end

      # Notify that a problem is occurred in the test. It means that
      # the test is a failed test. If any failed tests exist in test
      # suites, the test process exits with failure exit status.
      #
      # This is a public API for developers who extend test-unit.
      #
      # @return [void]
      def problem_occurred
        @internal_data.problem_occurred
      end

      # Notify that the test is passed. Normally, it is not needed
      # because #run calls it automatically. If you want to override
      # #run, it is not a good idea. Please contact test-unit
      # developers. We will help you without your custom #run. For
      # example, we may add a new hook in #run.
      #
      # This is a public API for developers who extend test-unit.
      #
      # @return [void]
      def add_pass
        current_result.add_pass
      end

      private
      def current_result
        @_result
      end

      def run_test
        signature = "#{self.class}\##{@method_name}"
        redefined_info = self[:redefined]
        if redefined_info
          notify("<#{signature}> was redefined",
                 :backtrace => redefined_info[:backtrace])
        end
        if self[:ractor] and not defined?(::Ractor)
          omit("<#{signature}> requires Ractor")
        end
        if @internal_data.have_test_data?
          test_method = method(@method_name)
          arity = test_method.arity
          if arity.zero?
            __send__(@method_name)
          else
            __send__(@method_name, @internal_data.test_data)
          end
        else
          __send__(@method_name)
        end
      end

      def handle_exception(exception)
        self.class.exception_handlers.each do |handler|
          if handler.respond_to?(:call)
            handled = handler.call(self, exception)
          else
            handled = __send__(handler, exception)
          end
          return true if handled
        end
        false
      end

      def add_assertion
        current_result.add_assertion
      end

      class InternalData
        attr_reader :start_time, :elapsed_time
        attr_reader :test_data_label, :test_data
        def initialize
          @start_time = nil
          @elapsed_time = nil
          @passed = true
          @interrupted = false
          @test_data_label = nil
          @test_data = nil
        end

        def passed?
          @passed
        end

        def interrupted?
          @interrupted
        end

        def assign_test_data(label, data)
          @test_data_label = label
          @test_data = data
        end

        def have_test_data?
          not @test_data_label.nil?
        end

        def test_started
          @start_time = Time.now
        end

        def test_finished
          @elapsed_time = Time.now - @start_time
        end

        def problem_occurred
          @passed = false
        end

        def interrupted
          @interrupted = true
        end
      end
    end
  end
end
