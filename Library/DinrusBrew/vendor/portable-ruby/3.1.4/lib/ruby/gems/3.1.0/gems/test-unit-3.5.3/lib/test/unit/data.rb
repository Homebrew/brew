require "test/unit/data-sets"

module Test
  module Unit
    module Data
      class << self
        def included(base)
          base.extend(ClassMethods)
        end
      end

      module ClassMethods
        # This method provides Data-Driven-Test functionality.
        #
        # Define test data in the test code.
        #
        # @overload data(label, data, options={})
        #   @param [String] label specify test case name.
        #   @param data specify test data.
        #   @param [Hash] options specify options.
        #   @option options [Boolean] :keep whether or not to use
        #     this data in the following test methods
        #
        #   @example data(label, data)
        #     data("empty string", [true, ""])
        #     data("plain string", [false, "hello"])
        #     def test_empty?(data)
        #       expected, target = data
        #       assert_equal(expected, target.empty?)
        #     end
        #
        # @overload data(variable, patterns, options={})
        #   @param [Symbol] variable specify test pattern variable name.
        #   @param [Array] patterns specify test patterns for the variable.
        #   @param [Hash] options specify options.
        #   @option options [Boolean] :keep whether or not to use
        #     this data in the following test methods
        #   @option options [Object] :group the test pattern group.
        #     Test matrix is generated for each test pattern group separately.
        #
        #   @example data(variable, patterns)
        #     data(:x, [1, 2, 3])
        #     data(:y, ["a", "b"])
        #     def test_patterns(data)
        #       # 3 * 2 times executed
        #       # 3: the number of patterns of :x
        #       # 2: the number of patterns of :y
        #       p data
        #         # => {:x => 1, :y => "a"}
        #         # => {:x => 1, :y => "b"}
        #         # => {:x => 2, :y => "a"}
        #         # => {:x => 2, :y => "b"}
        #         # => {:x => 3, :y => "a"}
        #         # => {:x => 3, :y => "b"}
        #     end
        #
        #   Generates test matrix from variable and patterns pairs.
        #
        # @overload data(data_set, options={})
        #   @param [Hash] data_set specify test data as a Hash that
        #     key is test label and value is test data.
        #   @param [Hash] options specify options.
        #   @option options [Boolean] :keep whether or not to use
        #     this data in the following test methods
        #
        #   @example data(data_set)
        #     data("empty string" => [true, ""],
        #          "plain string" => [false, "hello"])
        #     def test_empty?(data)
        #       expected, target = data
        #       assert_equal(expected, target.empty?)
        #     end
        #
        # @overload data(options={}, &block)
        #   @param [Hash] options specify options.
        #   @option options [Boolean] :keep whether or not to use
        #     this data in the following test methods
        #   @yieldreturn [Hash<String, Object>] return test data set
        #     as a Hash that key is test label and value is test data.
        #
        #   @example data(&block)
        #     data do
        #       data_set = {}
        #       data_set["empty string"] = [true, ""]
        #       data_set["plain string"] = [false, "hello"]
        #       data_set
        #     end
        #     def test_empty?(data)
        #       expected, target = data
        #       assert_equal(expected, target.empty?)
        #     end
        #
        # @overload data(options={}, &block)
        #   @param [Hash] options specify options.
        #   @option options [Boolean] :keep whether or not to use
        #     this data in the following test methods
        #   @yieldreturn [Array<Symbol, Array>] return test data set
        #     as an Array of variable and patterns.
        #
        #   @example data(&block)
        #     data do
        #       patterns = 3.times.to_a
        #       [:x, patterns]
        #     end
        #     data do
        #       patterns = []
        #       character = "a"
        #       2.times.each do
        #         patterns << character
        #         character = character.succ
        #       end
        #       [:y, patterns]
        #     end
        #     def test_patterns(data)
        #       # 3 * 2 times executed
        #       # 3: the number of patterns of :x
        #       # 2: the number of patterns of :y
        #       p data
        #         # => {:x => 0, :y => "a"}
        #         # => {:x => 0, :y => "b"}
        #         # => {:x => 1, :y => "a"}
        #         # => {:x => 1, :y => "b"}
        #         # => {:x => 2, :y => "a"}
        #         # => {:x => 2, :y => "b"}
        #     end
        #
        #   Generates test matrix from variable and patterns pairs.
        #
        def data(*arguments, &block)
          options = nil
          n_arguments = arguments.size
          case n_arguments
          when 0
            raise ArgumentError, "no block is given" unless block_given?
            data_set = block
          when 1
            if block_given?
              data_set = block
              options = arguments[0]
            else
              data_set = arguments[0]
            end
          when 2
            case arguments[0]
            when String
              data_set = {arguments[0] => arguments[1]}
            when Hash
              data_set = arguments[0]
              options = arguments[1]
            else
              variable = arguments[0]
              patterns = arguments[1]
              data_set = [variable, patterns]
            end
          when 3
            case arguments[0]
            when String
              data_set = {arguments[0] => arguments[1]}
              options = arguments[2]
            else
              variable = arguments[0]
              patterns = arguments[1]
              data_set = [variable, patterns]
              options = arguments[2]
            end
          else
            message = "wrong number arguments(#{n_arguments} for 0..3)"
            raise ArgumentError, message
          end
          options ||= {}
          data_sets = current_attribute(:data)[:value] || DataSets.new
          data_sets.add(data_set, options)
          if options[:keep] or data_sets.have_keep?
            keep_hook = lambda do |attr|
              attr.merge(value: attr[:value].keep)
            end
            options = options.merge(keep: true, keep_hook: keep_hook)
          end
          attribute(:data, data_sets, options)
        end

        # This method provides Data-Driven-Test functionality.
        #
        # Load test data from the file. This is shorthand to load
        # test data from file.  If you want to load complex file, you
        # can use {#data} with block.
        #
        # @param [String] file_name full path to test data file.
        #   File format is automatically detected from filename extension.
        # @raise [ArgumentError] if `file_name` is not supported file format.
        # @see Loader#load
        #
        # @example Load data from CSV file
        #   load_data("/path/to/test-data.csv")
        #   def test_empty?(data)
        #     assert_equal(data["expected"], data["target"].empty?)
        #   end
        #
        def load_data(file_name)
          loader = Loader.new(self)
          loader.load(file_name)
        end

        class Loader
          # @api private
          def initialize(test_case)
            @test_case = test_case
          end

          # Load data from file.
          #
          # @param [String] file_name full path to test data file.
          #   File format is automatically detected from filename extension.
          # @raise [ArgumentError] if `file_name` is not supported file format.
          # @see #load_csv
          # @see #load_tsv
          # @api private
          def load(file_name)
            case File.extname(file_name).downcase
            when ".csv"
              load_csv(file_name)
            when ".tsv"
              load_tsv(file_name)
            else
              raise ArgumentError, "unsupported file format: <#{file_name}>"
            end
          end

          # Load data from CSV file.
          #
          # There are 2 types of CSV file as following examples.
          # First, there is a header on first row and it's first column is "label".
          # Another, there is no header in the file.
          #
          # @example Load data from CSV file with header
          #   # test-data.csv:
          #   #  label,expected,target
          #   #  empty string,true,""
          #   #  plain string,false,hello
          #   #
          #   load_data("/path/to/test-data.csv")
          #   def test_empty?(data)
          #     assert_equal(data["expected"], data["target"].empty?)
          #   end
          #
          # @example Load data from CSV file without header
          #   # test-data-without-header.csv:
          #   #  empty string,true,""
          #   #  plain string,false,hello
          #   #
          #   load_data("/path/to/test-data-without-header.csv")
          #   def test_empty?(data)
          #     expected, target = data
          #     assert_equal(expected, target.empty?)
          #   end
          #
          # @api private
          def load_csv(file_name)
            require 'csv'
            first_row = true
            header = nil
            CSV.foreach(file_name) do |row|
              if first_row
                first_row = false
                if row.first == "label"
                  header = row[1..-1]
                  next
                end
              end

              set_test_data(header, row)
            end
          end

          # Load data from TSV file.
          #
          # There are 2 types of TSV file as following examples.
          # First, there is a header on first row and it's first column is "label".
          # Another, there is no header in the file.
          #
          # @example Load data from TSV file with header
          #   # test-data.tsv:
          #   #  label	expected	target
          #   #  empty string	true	""
          #   #  plain string	false	hello
          #   #
          #   load_data("/path/to/test-data.tsv")
          #   def test_empty?(data)
          #     assert_equal(data["expected"], data["target"].empty?)
          #   end
          #
          # @example Load data from TSV file without header
          #   # test-data-without-header.tsv:
          #   #  empty string	true	""
          #   #  plain string	false	hello
          #   #
          #   load_data("/path/to/test-data-without-header.tsv")
          #   def test_empty?(data)
          #     expected, target = data
          #     assert_equal(expected, target.empty?)
          #   end
          #
          # @api private
          def load_tsv(file_name)
            require "csv"
            if CSV.const_defined?(:VERSION)
              first_row = true
              header = nil
              CSV.foreach(file_name, :col_sep => "\t") do |row|
                if first_row
                  first_row = false
                  if row.first == "label"
                    header = row[1..-1]
                    next
                  end
                end

                set_test_data(header, row)
              end
            else
              # for old CSV library
              first_row = true
              header = nil
              CSV.open(file_name, "r", "\t") do |row|
                if first_row
                  first_row = false
                  if row.first == "label"
                    header = row[1..-1]
                    next
                  end
                end

                set_test_data(header, row)
              end
            end
          end

          private
          def normalize_value(value)
            return true if value == "true"
            return false if value == "false"
            begin
              Integer(value)
            rescue ArgumentError
              begin
                Float(value)
              rescue ArgumentError
                value
              end
            end
          end

          def set_test_data(header, row)
            label = row.shift
            if header
              data = {}
              header.each_with_index do |key, i|
                data[key] = normalize_value(row[i])
              end
            else
              data = row.collect do |cell|
                normalize_value(cell)
              end
            end
            @test_case.data(label, data)
          end
        end
      end
    end
  end
end
