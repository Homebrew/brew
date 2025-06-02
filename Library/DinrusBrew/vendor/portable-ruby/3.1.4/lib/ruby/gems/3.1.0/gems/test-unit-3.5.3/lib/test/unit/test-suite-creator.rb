#--
#
# Author:: Kouhei Sutou
# Copyright::
#   * Copyright (c) 2011 Kouhei Sutou <tt><kou@clear-code.com></tt>
# License:: Ruby license.

require "test/unit/data-sets"

module Test
  module Unit
    class TestSuiteCreator # :nodoc:
      class << self
        def test_method?(test_case, method_name)
          /\Atest./ =~ method_name.to_s or
            test_case.find_attribute(method_name, :test)
        end
      end

      def initialize(test_case)
        @test_case = test_case
      end

      def create
        suite = TestSuite.new(@test_case.name, @test_case)
        collect_test_names.each do |test_name|
          data_sets = extract_data_sets(test_name)
          if data_sets
            data_sets.each do |label, data|
              append_test(suite, test_name) do |test|
                test.assign_test_data(label, data)
              end
            end
          else
            append_test(suite, test_name)
          end
        end
        append_test(suite, "default_test") if suite.empty?
        suite
      end

      private
      def extract_data_sets(test_name)
        data_sets = @test_case.find_attribute(test_name,
                                              :data,
                                              :recursive => false)
        data_method_name = "data_#{test_name}"
        test = @test_case.new(test_name)
        if test.respond_to?(data_method_name)
          data_method = test.method(data_method_name)
          if data_method.arity <= 0
            data_sets ||= DataSets.new
            data_sets << data_method
          end
        end
        data_sets
      end

      def append_test(suite, test_name)
        test = @test_case.new(test_name)
        yield(test) if block_given?
        suite << test if test.valid?
      end

      def collect_test_names
        methods = @test_case.public_instance_methods(true)
        super_test_case = @test_case.superclass
        methods -= super_test_case.public_instance_methods(true)
        methods |= @test_case.public_instance_methods(false)
        method_names = methods.collect(&:to_s)
        test_names = method_names.find_all do |method_name|
          self.class.test_method?(@test_case, method_name)
        end
        __send__("sort_test_names_in_#{@test_case.test_order}_order", test_names)
      end

      def sort_test_names_in_alphabetic_order(test_names)
        test_names.sort
      end

      def sort_test_names_in_random_order(test_names)
        test_names.sort_by {rand(test_names.size)}
      end

      def sort_test_names_in_defined_order(test_names)
        added_method_names = @test_case.added_method_names
        test_names.sort do |test1, test2|
          test1_defined_order = added_method_names.index(test1)
          test2_defined_order = added_method_names.index(test2)
          if test1_defined_order and test2_defined_order
            test1_defined_order <=> test2_defined_order
          elsif test1_defined_order
            1
          elsif test2_defined_order
            -1
          else
            test1 <=> test2
          end
        end
      end
    end
  end
end
